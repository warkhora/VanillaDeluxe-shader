// VanillaDeluxe - the sky of the End: a dim violet void with a band of nebula light, and the Void
// Aurora: curtains of blue and violet light that wave slowly above the islands.
// Requires the global sampler noisetex.
#ifndef VD_END_SKY_INCLUDED
#define VD_END_SKY_INCLUDED 1

vec3 endBaseSky(vec3 dir, vec3 lightDir) {
	float band = pow(saturate(1.0 - abs(dir.y + 0.1) * 1.6), 3.0);
	float glow = pow(saturate(dot(dir, lightDir)), 16.0);
	return vec3(0.008, 0.005, 0.016) + vec3(0.034, 0.015, 0.062) * band + vec3(0.30, 0.18, 0.52) * glow;
}

// The aurora is a set of thin sheets hanging from a curved line across the sky, traced through
// several heights so that each sheet has a tall, rayed curtain below it. Fewer steps give a softer
// version, good enough for reflections and fog.
vec3 endAurora(vec3 dir, int steps) {
#ifdef END_AURORA
	if (dir.y < 0.015) return vec3(0.0);
	float t = frameTimeCounter * 0.03;
	vec3 sum = vec3(0.0);
	for (int i = 0; i < steps; i++) {
		float h = (float(i) + 0.5) / float(steps);
		// Points higher in the curtain lie further out along the same direction.
		vec2 p = dir.xz / (dir.y + 0.04) * (1.0 + h * 0.4);
		float bend = sin(p.x * 0.55 + t * 2.0) * 0.9 + sin(p.x * 1.31 - t * 3.1) * 0.35 + sin(p.y * 0.23 + t) * 0.6;
		float line = p.y * 0.8 + bend;
		float across = fract(line * 0.22) - 0.5;
		float sheet = exp(-across * across * 160.0);
		// Rays: the brightness changes along each sheet and drifts sideways.
		float rays = texture(noisetex, vec2(p.x * 0.05 + line * 0.015, t * 0.15)).r;
		rays = 0.30 + 0.70 * smoothstep(0.30, 0.85, rays);
		vec3 tint = mix(vec3(0.10, 0.40, 1.00), vec3(0.80, 0.22, 1.00), h);
		sum += tint * sheet * rays * (1.0 - h * 0.6);
	}
	float horizon = smoothstep(0.015, 0.22, dir.y) * (1.0 - 0.5 * smoothstep(0.7, 1.0, dir.y));
	return sum / float(steps) * horizon * 1.4 * float(END_AURORA_BRIGHTNESS) / 100.0;
#else
	return vec3(0.0);
#endif
}

#endif
