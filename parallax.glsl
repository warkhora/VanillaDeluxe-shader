// VanillaDeluxe - parallax occlusion mapping inside one tile of the block atlas.
// Requires a declared sampler named normals. Heights use the labPBR convention:
// the alpha channel of the normal map is 1.0 at the top of the surface.
#ifndef VD_PARALLAX_INCLUDED
#define VD_PARALLAX_INCLUDED 1

vec2 parallaxWrap(vec2 uv, vec2 mid, vec2 halfSize) {
	return mid + (fract((uv - mid) / (2.0 * halfSize) + 0.5) - 0.5) * 2.0 * halfSize;
}

// tangentEye points from the surface to the eye in tangent space.
vec2 parallaxOcclusion(vec2 uv, vec3 tangentEye, vec2 mid, vec2 halfSize, vec2 dx, vec2 dy, float fade, out float hitDepth) {
	hitDepth = 0.0;
	float first = textureGrad(normals, uv, dx, dy).a;
	if (first >= 0.998 && tangentEye.z > 0.95) return uv;

	float depthScale = float(POM_DEPTH) / 100.0 * fade;
	vec2 uvPerDepth = -tangentEye.xy / max(tangentEye.z, 0.18) * depthScale * 2.0 * halfSize;
	int steps = int(mix(float(POM_SAMPLES) * 0.4, float(POM_SAMPLES), 1.0 - saturate(tangentEye.z)) + 0.5);
	float layer = 1.0 / float(steps);
	vec2 stepUv = uvPerDepth * layer;

	vec2 current = uv;
	float currentDepth = 0.0;
	float surfaceDepth = 1.0 - first;
	float previousSurface = surfaceDepth;
	for (int i = 0; i < steps && currentDepth < surfaceDepth; i++) {
		current += stepUv;
		currentDepth += layer;
		previousSurface = surfaceDepth;
		surfaceDepth = 1.0 - textureGrad(normals, parallaxWrap(current, mid, halfSize), dx, dy).a;
	}
	// Linear interpolation between the last two layers removes the stair steps.
	float after = surfaceDepth - currentDepth;
	float before = previousSurface - (currentDepth - layer);
	float denominator = after - before;
	float w = abs(denominator) > 1e-5 ? saturate(after / denominator) : 0.0;
	vec2 hit = mix(current, current - stepUv, w);
	hitDepth = mix(currentDepth, currentDepth - layer, w) * depthScale;
	return parallaxWrap(hit, mid, halfSize);
}

// Light marched from the parallax hit point towards the sun. 1.0 means unoccluded.
float parallaxShadow(vec2 uv, float hitDepth, vec3 tangentLight, vec2 mid, vec2 halfSize, vec2 dx, vec2 dy, float fade) {
	if (tangentLight.z <= 0.02 || hitDepth <= 0.001) return 1.0;
	float depthScale = max(float(POM_DEPTH) / 100.0 * fade, 1e-4);
	vec2 uvPerDepth = tangentLight.xy / tangentLight.z * 2.0 * halfSize;
	const int SHADOW_STEPS = 8;
	float layer = hitDepth / float(SHADOW_STEPS);
	float occlusion = 0.0;
	for (int i = 1; i <= SHADOW_STEPS; i++) {
		float rayDepth = hitDepth - layer * float(i);
		vec2 p = parallaxWrap(uv + uvPerDepth * layer * float(i), mid, halfSize);
		float surface = (1.0 - textureGrad(normals, p, dx, dy).a) * depthScale;
		occlusion = max(occlusion, (rayDepth - surface) * (1.0 - float(i) / float(SHADOW_STEPS)));
	}
	return 1.0 - saturate(occlusion * 26.0);
}

#endif
