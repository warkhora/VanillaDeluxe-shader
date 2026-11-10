// VanillaDeluxe - deferred lighting of all opaque geometry and the sky.
#include "/lib/settings.glsl"
#include "/lib/common.glsl"

#ifdef VSH
out vec2 texCoord;
flat out vec3 vLight;
flat out vec3 vAmbientUp;
flat out vec3 vAmbientSide;
#include "/lib/sky.glsl"
void main() {
	gl_Position = ftransform();
	texCoord = gl_MultiTexCoord0.xy;
	vLight = readLightColor();
	vAmbientUp = readAmbientUp();
	vAmbientSide = readAmbientSide();
}
#endif

#ifdef FSH
in vec2 texCoord;
flat in vec3 vLight;
flat in vec3 vAmbientUp;
flat in vec3 vAmbientSide;

uniform sampler2D depthtex0;
uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex3;
#ifdef RAY_TRACING
uniform sampler2D colortex19;
#define INDIRECT_LIGHT colortex19
#else
uniform sampler2D colortex10;
#define INDIRECT_LIGHT colortex10
#endif
uniform sampler2D colortex14;
uniform sampler2D noisetex;
uniform int heldBlockLightValue;
uniform int heldBlockLightValue2;

#include "/lib/sky.glsl"
#include "/lib/shadow.glsl"
#include "/lib/brdf.glsl"
#include "/lib/clouds.glsl"
#if DIM_ID == 1
#include "/lib/end_sky.glsl"
#endif
#ifdef USE_RT_LIGHT
#include "/lib/rt_light.glsl"
#endif

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outColor;

vec3 renderSky(vec3 dir, vec3 skyObjects) {
	vec3 color = skyColorInDirection(dir);
#if DIM_ID == 0
	vec3 sunDir = worldSunDir();
	float cosSun = dot(dir, sunDir);
	float horizon = smoothstep(-0.015, 0.02, dir.y);
	float clearSky = 1.0 - rainStrength * 0.97;
	if (cosSun > 0.9995) {
		float disc = smoothstep(0.99990, 0.99996, cosSun);
		float limb = mix(0.55, 1.0, sqrt(saturate((cosSun - 0.9999) / 0.0001)));
		color += vLight * disc * limb * 7.0 * horizon * clearSky;
	}
	float night = smoothstep(0.08, -0.06, sunDir.y);
	color += skyObjects * horizon * clearSky * mix(0.08, 1.0, night);
#elif DIM_ID == 1
	// The sky of the End in full detail, with the aurora, instead of the coarse version in the
	// sky table, which reflections and fog use.
	color = endBaseSky(dir, worldLightDir()) + endAurora(dir, 14);
	// Procedural stars for the End. The vanilla sky box is not used here.
	vec3 grid = floor(dir * 190.0);
	float star = fract(sin(dot(grid, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	color += vec3(0.86, 0.80, 1.0) * smoothstep(0.9965, 1.0, star) * 0.9;
#endif
	return color;
}

// Reads the half resolution indirect light with depth-aware weights. Each texel of it was
// traced at the lower left pixel of its 2 x 2 block, so that is where it sits on the screen.
vec4 readIndirect(ivec2 px, float linearZ) {
#ifdef USE_INDIRECT
	ivec2 base = px >> 1;
	ivec2 bounds = ivec2(viewWidth, viewHeight) / 2 - 1;
	vec4 sum = vec4(0.0);
	float total = 0.0;
	for (int y = 0; y <= 1; y++) {
		for (int x = 0; x <= 1; x++) {
			ivec2 p = clamp(base + ivec2(x, y), ivec2(0), bounds);
			vec2 history = texelFetch(colortex14, p, 0).rg;
			float z = history.r;
			vec2 fullCenter = vec2(p * 2) + 0.5;
			vec2 d = (vec2(px) + 0.5 - fullCenter) * 0.5;
			float spatial = max(1.0 - abs(d.x), 0.02) * max(1.0 - abs(d.y), 0.02);
			float depthWeight = exp(-abs(z - linearZ) / (0.02 * linearZ + 0.05));
			float w = spatial * depthWeight + 1e-4;
			// Occlusion from a few frames is mostly noise. Without this, pixels revealed at the
			// screen edge while turning show up as a dark band until they have settled.
			vec4 indirectSample = texelFetch(INDIRECT_LIGHT, p, 0);
			indirectSample.a = mix(1.0, indirectSample.a, saturate((history.g + 1.0) / 7.0));
			sum += indirectSample * w;
			total += w;
		}
	}
	return sum / total;
#else
	return vec4(0.0, 0.0, 0.0, 1.0);
#endif
}

void main() {
	ivec2 px = ivec2(gl_FragCoord.xy);
	vec2 uv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
	float depth = texelFetch(depthtex0, px, 0).r;
	vec3 layer = texelFetch(colortex0, px, 0).rgb;
	vec3 viewPos = viewFromScreen(uv, depth);
	vec3 feet = viewToFeet(viewPos);
	vec3 worldDir = normalize(feet);

	if (depth >= 1.0) {
		vec3 sky = renderSky(worldDir, layer);
		outColor = vec4(clamp(sky, vec3(0.0), vec3(400.0)), 1.0);
		return;
	}

	vec4 normalLight = texelFetch(colortex1, px, 0);
	vec4 material = texelFetch(colortex2, px, 0);
	vec4 geometry = texelFetch(colortex3, px, 0);

	int materialClass = unpackMaterialClass(geometry.b);
	float parallaxLight = unpackParallaxShadow(geometry.b);
	float vanillaAo = geometry.a;
	vec3 albedo = layer;
	vec3 N = decodeNormal(normalLight.rg);
	vec3 Ng = decodeNormal(geometry.rg);
	float lmBlock = normalLight.b;
	float lmSky = normalLight.a;

	float smoothness = material.r;
	float roughness = (1.0 - smoothness) * (1.0 - smoothness);
	vec3 f0;
	float metalness;
	decodeReflectance(material.g, albedo, f0, metalness);
	float emission = material.b;
	float subsurface = decodeSubsurface(material.a);

	// The hand is drawn with its own projection. Shade it as if it were at the eye.
	if (materialClass == MAT_HAND) {
		viewPos = normalize(viewPos) * 0.6;
		feet = viewToFeet(viewPos);
	}
	float linearZ = -viewPos.z;
	float dist = length(viewPos);

	vec3 V = normalize(-viewPos);
	vec3 L = normalize(shadowLightPosition);
	vec3 Nw = mat3(gbufferModelViewInverse) * N;
	vec3 Ngw = mat3(gbufferModelViewInverse) * Ng;
	vec3 worldPos = feet + cameraPosition;

	float NoL = saturate(dot(N, L));
	float NgoL = dot(Ng, L);
	float NoV = max(dot(N, V), 1e-3);

	vec4 indirectData = materialClass == MAT_HAND ? vec4(0.0, 0.0, 0.0, 1.0) : readIndirect(px, linearZ);
	float ao = vanillaAo * indirectData.a;

	// ---- Direct light --------------------------------------------------
	vec3 direct = vec3(0.0);
	vec3 transmittedLight = vec3(0.0);
#ifdef HAS_SHADOWS
	bool facing = NgoL > 0.0 || subsurface > 0.0;
	if (facing && dot(vLight, vLight) > 1e-7 && materialClass != MAT_UNLIT && materialClass != MAT_CLOUD) {
		float transmitted = 1.0;
		// The filter rotation repeats every 8 frames, which TAA averages into a steady penumbra.
		vec3 visibility = sampleShadow(feet, Ngw, cycleNoise(gl_FragCoord.xy + vec2(13.0, 71.0), 8, NOISE_STEP_A), transmitted);
#ifdef HAS_SKYLIGHT
		// Beyond the shadow map, sealed caves must stay dark.
		visibility *= smoothstep(0.0, 0.18, lmSky);
#endif
		visibility *= parallaxLight;
#if defined VOLUMETRIC_CLOUDS && defined CLOUD_SHADOWS && DIM_ID == 0
		visibility *= cloudShadowAt(worldPos, worldLightDir());
#endif
		if (NgoL > 0.0) {
			vec3 H = normalize(V + L);
			float VoH = saturate(dot(V, H));
			float diffuse = diffuseBurley(NoL, NoV, VoH, roughness) * NoL;
			direct = vLight * visibility * (albedo * (1.0 - metalness) * diffuse);
#ifdef SPECULAR_HIGHLIGHTS
			direct += vLight * visibility * specularGGX(N, V, L, roughness, f0);
#endif
		}
#ifdef SUBSURFACE_SCATTERING
		if (subsurface > 0.0) {
			float cosView = dot(V, -L);
			float phase = phaseHG(cosView, 0.65) * 4.0 + 0.35;
			float back = NgoL > 0.0 ? 0.35 : 1.0;
			vec3 tinted = albedo * sqrt(max(albedo, vec3(0.0)));
			transmittedLight = vLight * tinted * subsurface * transmitted * phase * back * INV_PI
				* mix(vec3(1.0), visibility, 0.35) * float(SSS_STRENGTH) / 100.0;
		}
#endif
	}
#endif

	// ---- Ambient and block light ---------------------------------------
	vec3 ambient = skyAmbient(Nw, vAmbientUp, vAmbientSide);
#ifdef HAS_SKYLIGHT
	ambient = applySkyOcclusion(ambient, lmSky);
	// Light reflected back up from the ground in open air.
	float bounce = saturate(-Nw.y * 0.5 + 0.5) * lmSky * lmSky;
	ambient += vLight * 0.018 * bounce * vec3(0.95, 1.0, 0.82) * saturate(worldLightDir().y);
#endif

	float blockCurve = lmBlock * lmBlock;
	blockCurve = blockCurve * (0.22 + 1.05 * blockCurve);
#ifdef USE_RT_LIGHT
	// The ray traced light has arrived with the indirect light. The hand gets none of that.
	if (lmBlock > 0.01 && materialClass != MAT_HAND) blockCurve *= rtLightmapScale(feet);
#endif
#ifdef HAND_DYNAMIC_LIGHT
	float heldLight = float(max(heldBlockLightValue, heldBlockLightValue2));
	if (heldLight > 0.0) {
		float reach = saturate(1.0 - dist / (heldLight * 0.95));
		float handCurve = reach * reach;
		blockCurve = max(blockCurve, handCurve * 1.1 * heldLight / 15.0);
	}
#endif
	vec3 blockColor = vec3(1.0, 0.52, 0.24) * blockCurve * 1.35 * float(BLOCKLIGHT_STRENGTH) / 100.0;

	vec3 minimumLight = vec3(0.011, 0.012, 0.015) * float(MIN_LIGHT) / 100.0;
	minimumLight += vec3(0.30, 0.34, 0.30) * nightVision;

	vec3 diffuseLight = (ambient + blockColor + minimumLight) * ao + indirectData.rgb * vanillaAo;
#ifdef SUBSURFACE_SCATTERING
	// Leaves and plants also pass on some of the light of the sky that falls on their other side,
	// which keeps the underside of a canopy green instead of grey.
	if (subsurface > 0.0) diffuseLight += ambient * subsurface * sqrt(max(albedo, vec3(0.0))) * 0.35 * float(SSS_STRENGTH) / 100.0 * ao;
#endif
	vec3 color = albedo * (1.0 - metalness) * diffuseLight;

	color += direct + transmittedLight;


	// ---- Environment reflection for surfaces that are not screen traced --
	float fresnelStrength = pow5(1.0 - NoV);
	vec3 envFresnel = f0 + (max(vec3(1.0 - roughness), f0) - f0) * fresnelStrength;
#if defined SCREEN_SPACE_REFLECTIONS && defined SSR_ON_SURFACES
	bool tracedLater = smoothness >= 0.45 || metalness > 0.5;
#else
	bool tracedLater = false;
#endif
	if (!tracedLater) {
		vec3 R = reflect(-V, N);
		vec3 Rw = mat3(gbufferModelViewInverse) * R;
		vec3 env = skyColorInDirection(Rw) * (1.0 - roughness * 0.75);
#ifdef HAS_SKYLIGHT
		env *= lmSky * lmSky * lmSky;
#endif
		color += envFresnel * (env * saturate(ao * 1.2) + blockColor * 0.25 * roughness);
	}

	// ---- Emission ------------------------------------------------------
	if (materialClass == MAT_UNLIT) {
		color = albedo * max(emission, 0.5) * 3.2;
	} else if (materialClass == MAT_CLOUD) {
		color = albedo * (vAmbientUp * 1.4 + vLight * INV_PI * 0.75);
	}
	if (materialClass != MAT_UNLIT) color += surfaceEmission(albedo, emission, materialClass);

	color *= 1.0 - darknessFactor * 0.8;
	if (any(isnan(color)) || any(isinf(color))) color = vec3(0.0);
	// The reflection pass cannot read albedo any more, so metals keep their colour here.
	outColor = vec4(clamp(color, vec3(0.0), vec3(400.0)), metalness > 0.5 ? packMetalTint(f0) : 0.0);
}
#endif
