// VanillaDeluxe - refraction vectors for ice and glass, from Snell's law.
// The surface normal alone says nothing about displacement: a flat surface has the same
// normal everywhere, and offsetting by it would shift the whole image. These functions
// follow the bent ray to a point in view space and project that point instead.
#ifndef VD_REFRACTION_INCLUDED
#define VD_REFRACTION_INCLUDED 1

// Screen position of a view space point, or the fallback if it is behind the camera.
vec2 projectOrKeep(vec3 point, vec2 fallback) {
	if (point.z > -near) return fallback;
	return screenFromView(point).xy;
}

// A solid body such as ice: the ray stays bent until it reaches what lies behind.
vec2 refractThroughSolid(vec3 viewPos, vec3 N, vec3 V, float ior, float path, vec2 fallback) {
	vec3 inside = refract(-V, N, 1.0 / ior);
	if (dot(inside, inside) < 0.5) return fallback;
	return projectOrKeep(viewPos + inside * path, fallback);
}

// A thin pane: the ray leaves parallel to how it entered, only shifted sideways. The shift
// is zero when looking straight at the pane, and shrinks on screen with distance.
vec2 refractThroughPane(vec3 viewPos, vec3 N, vec3 V, float ior, float thickness, float beyond, vec2 fallback) {
	vec3 inside = refract(-V, N, 1.0 / ior);
	if (dot(inside, inside) < 0.5) return fallback;
	float crossing = thickness / max(dot(-inside, N), 0.2);
	return projectOrKeep(viewPos + inside * crossing - V * beyond, fallback);
}

#endif
