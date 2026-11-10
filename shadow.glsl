// VanillaDeluxe - shadow map distortion, contact-hardening filter and tinting.
#ifndef VD_SHADOW_INCLUDED
#define VD_SHADOW_INCLUDED 1

const float SHADOW_DISTORTION = 0.88;

float shadowDistortionFactor(vec2 ndc) {
	vec2 a = ndc * ndc;
	float r = sqrt(sqrt(a.x * a.x + a.y * a.y));
	return r * SHADOW_DISTORTION + (1.0 - SHADOW_DISTORTION);
}
vec2 distortShadowNdc(vec2 ndc) {
	return ndc / shadowDistortionFactor(ndc);
}
vec3 feetToShadowNdc(vec3 feet) {
	vec3 v = mat3(shadowModelView) * feet + shadowModelView[3].xyz;
	return vec3(shadowProjection[0][0], shadowProjection[1][1], shadowProjection[2][2]) * v + shadowProjection[3].xyz;
}

#ifdef HAS_SHADOWS
#ifndef SHADOW_PASS

uniform sampler2D shadowtex0;
uniform sampler2DShadow shadowtex1;
uniform sampler2D shadowcolor0;

const float SHADOW_SUN_TAN = 0.012;
const vec3 SHADOW_WATER_ABSORPTION = vec3(0.34, 0.075, 0.035);

// Depth units of the shadow map per block of distance along the light.
float shadowDepthPerBlock() {
	return abs(shadowProjection[2][2]) * 0.5;
}

// Fast single tap with the hardware bilinear filter. Used by the fog raymarch.
float shadowVisibilityFast(vec3 feet) {
	vec3 ndc = feetToShadowNdc(feet);
	if (abs(ndc.x) >= 1.0 || abs(ndc.y) >= 1.0) return 1.0;
	vec3 coord = vec3(distortShadowNdc(ndc.xy) * 0.5 + 0.5, ndc.z * 0.5 + 0.5);
	return texture(shadowtex1, vec3(coord.xy, coord.z - 0.0002));
}

// Fades towards full light outside of the shadow map.
float shadowEdgeFade(vec3 ndc) {
	float r = max(abs(ndc.x), abs(ndc.y));
	return smoothstep(0.82, 0.98, r);
}

// Contact-hardening shadow. Returns coloured visibility and writes the amount of
// light that passes through thin geometry for subsurface scattering.
vec3 sampleShadow(vec3 feet, vec3 worldGeomNormal, float dither, out float transmitted) {
	transmitted = 1.0;
	vec3 lightDir = worldLightDir();
	float cosLight = dot(worldGeomNormal, lightDir);

	vec3 ndc = feetToShadowNdc(feet);
	float fade = shadowEdgeFade(ndc);
	if (fade >= 1.0) return vec3(1.0);

	// Offset along the normal by the world size of a shadow texel at this point.
	float factor = shadowDistortionFactor(ndc.xy);
	float blocksPerUv = 2.0 * shadowDistance * factor;
	float texelBlocks = blocksPerUv / float(shadowMapResolution);
	float offset = texelBlocks * (1.2 + 2.2 * (1.0 - saturate(abs(cosLight)))) + 0.012;
	vec3 biasedFeet = feet + worldGeomNormal * offset;
	ndc = feetToShadowNdc(biasedFeet);

	vec2 uv = distortShadowNdc(ndc.xy) * 0.5 + 0.5;
	float z = ndc.z * 0.5 + 0.5;
	float depthPerBlock = shadowDepthPerBlock();
	float uvPerBlock = 1.0 / blocksPerUv;

	// Receiver plane slope turned into a depth bias per unit of uv offset.
	float tanLight = min(sqrt(max(1.0 - cosLight * cosLight, 0.0)) / max(abs(cosLight), 0.12), 5.0);
	float slopeBias = tanLight * blocksPerUv * depthPerBlock;
	float baseBias = 0.00002;

	float angle = dither * TAU;
	vec2 dir = vec2(cos(angle), sin(angle));
	const mat2 goldenRotation = mat2(-0.73736882, 0.67549029, -0.67549029, -0.73736882);

	float minRadius = 1.1 / float(shadowMapResolution);
	float filterRadius = minRadius;
	float lightTan = SHADOW_SUN_TAN * float(SHADOW_PENUMBRA_SIZE) / 100.0;
	float blockerAverage = z;

#ifdef VARIABLE_PENUMBRA
	float searchRadius = max(lightTan * 90.0 * uvPerBlock, minRadius * 2.0);
	float blockerSum = 0.0;
	float blockerCount = 0.0;
	for (int i = 0; i < SHADOW_BLOCKER_SAMPLES; i++) {
		float radial = sqrt((float(i) + 0.5) / float(SHADOW_BLOCKER_SAMPLES));
		vec2 o = dir * radial * searchRadius;
		dir = goldenRotation * dir;
		float d = texture(shadowtex0, uv + o).r;
		if (d < z - baseBias - radial * searchRadius * slopeBias) {
			blockerSum += d;
			blockerCount += 1.0;
		}
	}
	if (blockerCount < 0.5) return vec3(1.0);
	blockerAverage = blockerSum / blockerCount;
	float penumbraBlocks = max(z - blockerAverage, 0.0) / depthPerBlock * lightTan;
	filterRadius = max(penumbraBlocks * uvPerBlock, minRadius);
#else
	filterRadius = max(lightTan * 2.0 * uvPerBlock, minRadius);
	float rawDepth = texture(shadowtex0, uv).r;
	blockerAverage = min(rawDepth, z);
#endif

	transmitted = exp(-max(z - blockerAverage, 0.0) / depthPerBlock * 1.6);

	float visibility = 0.0;
	for (int i = 0; i < SHADOW_FILTER_SAMPLES; i++) {
		float radial = sqrt((float(i) + 0.5) / float(SHADOW_FILTER_SAMPLES));
		vec2 o = dir * radial * filterRadius;
		dir = goldenRotation * dir;
		visibility += texture(shadowtex1, vec3(uv + o, z - baseBias - radial * filterRadius * slopeBias));
	}
	visibility /= float(SHADOW_FILTER_SAMPLES);

	vec3 tint = vec3(1.0);
#ifdef COLORED_SHADOWS
	if (visibility > 0.0) {
		vec2 tintUv = uv + dir * filterRadius * 0.5;
		float translucentDepth = texture(shadowtex0, tintUv).r;
		if (translucentDepth < z - baseBias) {
			vec4 c = texture(shadowcolor0, tintUv);
			if (c.a < 0.4) {
				// Water: rgb holds the caustic intensity, absorption grows with path length.
				float path = (z - translucentDepth) / depthPerBlock;
				// The pattern fades with depth, because light from a wide sky evens it out.
				float pattern = c.r * 2.0;
				float strength = 0.55 * exp(-path * 0.12);
				tint = vec3(mix(1.0, pattern, strength)) * exp(-SHADOW_WATER_ABSORPTION * path * float(WATER_ABSORPTION) / 100.0);
			} else {
				tint = mix(vec3(1.0), c.rgb, saturate((c.a - 0.5) * 2.0));
			}
		}
	}
#endif

	vec3 result = visibility * tint;
	return mix(result, vec3(1.0), fade);
}

#endif
#endif

#endif
