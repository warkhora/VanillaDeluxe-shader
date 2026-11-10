// VanillaDeluxe - screen-space ray tracing against the opaque depth buffer.
// Requires global samplers depthtex1. Steps grow quadratically along the ray, which
// keeps contact reflections sharp without spending samples on empty distance.
#ifndef VD_SSR_INCLUDED
#define VD_SSR_INCLUDED 1

bool traceScreenRay(vec3 viewPos, vec3 dir, float dither, out vec2 hitUv) {
	hitUv = vec2(0.0);
	float rayLength = 512.0;
	if (dir.z > 0.0) rayLength = min(rayLength, (-near * 1.5 - viewPos.z) / dir.z);
	if (rayLength <= 0.0) return false;

	vec3 start = screenFromView(viewPos);
	vec3 end = screenFromView(viewPos + dir * rayLength);
	vec3 delta = end - start;

	// Clip the ray to the screen so that no steps are spent outside of it.
	float clip = 1.0;
	if (delta.x > 0.0) clip = min(clip, (1.0 - start.x) / delta.x);
	else if (delta.x < 0.0) clip = min(clip, -start.x / delta.x);
	if (delta.y > 0.0) clip = min(clip, (1.0 - start.y) / delta.y);
	else if (delta.y < 0.0) clip = min(clip, -start.y / delta.y);
	delta *= max(clip, 0.0);

	float previousS = 0.0;
	float stepsF = float(SSR_STEPS);
	for (int i = 0; i < SSR_STEPS; i++) {
		float s = (float(i) + dither) / stepsF;
		s = s * s * 0.985 + 0.015 * s;
		vec3 p = start + delta * s;
		if (p.z >= 1.0) return false;
		float sceneDepth = texture(depthtex1, p.xy).r;
		if (sceneDepth < p.z) {
			// Binary refinement between the last free and first blocked position.
			float low = previousS;
			float high = s;
			for (int j = 0; j < SSR_REFINE; j++) {
				float mid = 0.5 * (low + high);
				vec3 q = start + delta * mid;
				if (texture(depthtex1, q.xy).r < q.z) high = mid;
				else low = mid;
			}
			vec3 hit = start + delta * high;
			float hitDepth = texture(depthtex1, hit.xy).r;
			if (hitDepth >= 1.0) return false;
			float stepLinear = linearDepth(hit.z) - linearDepth(start.z + delta.z * low);
			float gap = linearDepth(hit.z) - linearDepth(hitDepth);
			if (gap < max(abs(stepLinear) * 2.0, 0.6) + linearDepth(hit.z) * 0.012) {
				hitUv = hit.xy;
				return true;
			}
		}
		previousS = s;
	}
	return false;
}

#endif
