// VanillaDeluxe - procedural surface detail for lava and ice.
// Requires common.glsl and a declared noisetex sampler.
#ifndef VD_SURFACE_DETAIL_INCLUDED
#define VD_SURFACE_DETAIL_INCLUDED 1

// Tilts a world space normal by the slope of a noise field across the face it belongs to.
vec3 perturbWorldNormal(vec3 n, vec3 worldPos, float frequency, float amount) {
	vec3 a = abs(n);
	vec2 p = a.y >= a.x && a.y >= a.z ? worldPos.xz : (a.x >= a.z ? worldPos.zy : worldPos.xy);
	const float e = 0.3;
	float h = texture(noisetex, p * frequency).r;
	vec2 slope = vec2(texture(noisetex, (p + vec2(e, 0.0)) * frequency).r - h,
		texture(noisetex, (p + vec2(0.0, e)) * frequency).r - h) * amount;
	vec3 offset = a.y >= a.x && a.y >= a.z ? vec3(slope.x, 0.0, slope.y)
		: (a.x >= a.z ? vec3(0.0, slope.y, slope.x) : vec3(slope.x, slope.y, 0.0));
	return normalize(n - offset);
}

// Slow drifting brightness of molten rock. Averages 1.0, ranges from 0.78 to 1.22.
float lavaPulse(vec3 worldPos) {
	float t = frameTimeCounter;
	float a = texture(noisetex, worldPos.xz * 0.004 + t * vec2(0.0021, 0.0013)).r;
	float b = texture(noisetex, worldPos.xz * 0.011 - t * vec2(0.0034, 0.0049)).g;
	return 0.78 + 0.44 * (a * 0.6 + b * 0.4);
}

#endif
