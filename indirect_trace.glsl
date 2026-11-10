// VanillaDeluxe - half resolution ambient occlusion and indirect light. Occlusion comes from
// one screen-space slice per pixel with a visibility bitmask (after Therrien et al. 2023).
// With ray tracing, bounce light comes from paths through the depth buffer, and block light
// from shadow rays through the voxel scene. Without it, a short range gather along the same
// slice gives the bounce light. All of it is noisy on its own. The temporal and denoising
// passes that follow clean it up.
#include "/lib/settings.glsl"
#include "/lib/common.glsl"

#ifdef VSH
out vec2 texCoord;
void main() {
	gl_Position = ftransform();
	texCoord = gl_MultiTexCoord0.xy;
}
#endif

#ifdef FSH
in vec2 texCoord;

uniform sampler2D depthtex0;
uniform sampler2D colortex3;
#if defined SCREEN_SPACE_GI && !defined USE_RT_GI
uniform sampler2D colortex7;
#endif
#if defined USE_RT_LIGHT || defined USE_RT_GI
uniform sampler2D colortex1;
uniform sampler2D colortex2;
#endif
#ifdef USE_RT_GI
uniform sampler2D colortex0;
#include "/lib/sky.glsl"
#include "/lib/shadow.glsl"
#endif

/* RENDERTARGETS: 6 */
layout(location = 0) out vec4 outTrace;

#ifdef USE_RT_LIGHT
#include "/lib/rt_light.glsl"
#endif
#ifdef USE_RT_GI
#include "/lib/ssgi.glsl"
#endif

#ifdef SCREEN_SPACE_AO

const uint SECTORS = 32u;

uint horizonMask(float minHorizon, float maxHorizon) {
	uint start = min(uint(saturate(minHorizon) * float(SECTORS)), SECTORS - 1u);
	uint width = uint(ceil(saturate(maxHorizon - minHorizon) * float(SECTORS)));
	if (width == 0u) return 0u;
	uint bits = width >= SECTORS ? 0xFFFFFFFFu : (0xFFFFFFFFu >> (SECTORS - width));
	return bits << start;
}

#endif

void main() {
	ivec2 fullPx = ivec2(gl_FragCoord.xy * 2.0);
	vec2 viewSize = vec2(viewWidth, viewHeight);
	float depth = texelFetch(depthtex0, fullPx, 0).r;
	vec4 geometry = texelFetch(colortex3, fullPx, 0);

	outTrace = vec4(0.0, 0.0, 0.0, 1.0);
	if (depth >= 1.0) return;
#ifdef USE_INDIRECT
	int materialClass = unpackMaterialClass(geometry.b);
	if (materialClass == MAT_HAND || materialClass == MAT_UNLIT || materialClass == MAT_CLOUD) return;

	vec2 uv = (vec2(fullPx) + 0.5) / viewSize;
	vec3 P = viewFromScreen(uv, depth);
	vec3 N = decodeNormal(geometry.rg);
	vec3 V = normalize(-P);
	float viewDist = -P.z;
	P += N * viewDist * 0.0008;

	// All noise of this pass repeats every 16 frames. The temporal pass keeps more history than
	// that, so it settles on the same average in every frame instead of drifting around it.
	float noiseAngle = cycleNoise(gl_FragCoord.xy, 16, NOISE_STEP_A);
	float noiseStep = cycleNoise(gl_FragCoord.xy + vec2(47.0, 17.0), 16, NOISE_STEP_B);

	float ao = 1.0;
	vec3 indirect = vec3(0.0);

#ifdef SCREEN_SPACE_AO
	float worldRadius = float(AO_RADIUS) / 10.0;
	float screenRadius = worldRadius * gbufferProjection[1][1] * 0.5 / max(viewDist, 0.1);
	screenRadius = clamp(screenRadius, 6.0 / viewHeight, 0.28);
	vec2 radiusUv = vec2(screenRadius / aspectRatio, screenRadius);

	float phi = noiseAngle * PI;
	vec2 omega = vec2(cos(phi), sin(phi));
	vec3 direction = vec3(omega, 0.0);
	vec3 orthoDirection = direction - dot(direction, V) * V;
	vec3 axis = normalize(cross(direction, V));
	vec3 projectedN = N - axis * dot(N, axis);
	float projectedLength = max(length(projectedN), 1e-4);
	float signN = dot(orthoDirection, projectedN) >= 0.0 ? 1.0 : -1.0;
	float cosN = saturate(dot(projectedN / projectedLength, V));
	float n = signN * acos(cosN);

	// Reprojection offset of this pixel, used for all colour lookups of the short range gather.
	vec2 historyOffset = vec2(0.0);
#if defined SCREEN_SPACE_GI && !defined USE_RT_GI
	historyOffset = reprojectFeet(viewToFeet(P)).xy - uv;
#endif

	float thickness = max(0.75, viewDist * 0.02);
	uint occluded = 0u;
	vec3 gathered = vec3(0.0);

	for (int sideIndex = 0; sideIndex < 2; sideIndex++) {
		float side = sideIndex == 0 ? 1.0 : -1.0;
		for (int i = 0; i < AO_STEPS; i++) {
			float s = (float(i) + noiseStep) / float(AO_STEPS);
			s = s * s + 0.004;
			vec2 sampleUv = uv - side * s * radiusUv * omega;
			if (sampleUv.x <= 0.0 || sampleUv.y <= 0.0 || sampleUv.x >= 1.0 || sampleUv.y >= 1.0) break;

			float sampleDepth = texelFetch(depthtex0, ivec2(sampleUv * viewSize), 0).r;
			if (sampleDepth >= 1.0) continue;
			vec3 samplePos = viewFromScreen(sampleUv, sampleDepth);
			vec3 delta = samplePos - P;
			float deltaLength = length(delta);
			if (deltaLength < 1e-4 || deltaLength > worldRadius * 2.5) continue;
			vec3 deltaBack = delta - V * thickness;

			float frontCos = dot(delta / deltaLength, V);
			float backCos = dot(normalize(deltaBack), V);
			vec2 angles = acos(clamp(vec2(frontCos, backCos), -1.0, 1.0));
			vec2 horizons = saturate((side * -angles - n + HALF_PI) / PI);
			float low = min(horizons.x, horizons.y);
			float high = max(horizons.x, horizons.y);

			uint mask = horizonMask(low, high);
			uint newBits = mask & ~occluded;
			occluded |= mask;
#if defined SCREEN_SPACE_GI && !defined USE_RT_GI
			if (newBits != 0u) {
				vec2 historyUv = sampleUv + historyOffset;
				vec3 sampleColor = textureLod(colortex7, historyUv, 0.0).rgb;
				float cosTerm = saturate(dot(N, delta / deltaLength));
				gathered += sampleColor * cosTerm * float(bitCount(newBits)) / float(SECTORS);
			}
#endif
		}
	}

	ao = 1.0 - float(bitCount(occluded)) / float(SECTORS);
	ao = pow(saturate(ao), float(AO_STRENGTH) / 100.0);
#if defined SCREEN_SPACE_GI && !defined USE_RT_GI
	indirect = min(gathered * HALF_PI * float(GI_STRENGTH) / 100.0, vec3(8.0));
#endif
#endif

#ifdef USE_RT_GI
	vec2 rayNoise = vec2(cycleNoise(gl_FragCoord.xy + vec2(83.0, 29.0), 16, NOISE_STEP_B), cycleNoise(gl_FragCoord.xy + vec2(11.0, 137.0), 16, NOISE_STEP_C));
	indirect = traceBounceLight(P, N, rayNoise, noiseStep, ivec2(gl_FragCoord.xy)) * float(GI_STRENGTH) / 100.0;
	// Enough headroom for lava and glowstone to tint a wall, without single bright dots.
	float rayLuminance = luminance(indirect);
	if (rayLuminance > 16.0) indirect *= 16.0 / rayLuminance;
#endif

#ifdef USE_RT_LIGHT
	// Vanilla light levels reach exactly as far as any light source can, so a pixel without block
	// light needs no ray. That makes this free in daylight, far away from any torch.
	if (materialClass != MAT_LAVA && texelFetch(colortex1, fullPx, 0).b > 0.01) {
		vec4 lightNoise = vec4(
			cycleNoise(gl_FragCoord.xy + vec2(191.0, 67.0), 16, NOISE_STEP_A),
			cycleNoise(gl_FragCoord.xy + vec2(31.0, 223.0), 16, NOISE_STEP_B),
			cycleNoise(gl_FragCoord.xy + vec2(109.0, 3.0), 16, NOISE_STEP_C),
			cycleNoise(gl_FragCoord.xy + vec2(251.0, 149.0), 16, NOISE_STEP_D));
		indirect += rtBlockLight(viewToFeet(P), mat3(gbufferModelViewInverse) * N, materialClass == MAT_FOLIAGE, lightNoise, true);
	}
#endif
	outTrace = vec4(indirect, ao);
#endif
}
#endif
