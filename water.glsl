// VanillaDeluxe - procedural water surface and water volume.
#ifndef VD_WATER_INCLUDED
#define VD_WATER_INCLUDED 1

// Sum of exponentiated sine waves with domain warping. The gradient is accumulated
// analytically, so one evaluation gives the normal without finite differences.
// footprint is the size of a pixel on the water in blocks. Waves smaller than that fade out,
// because a pixel would pick a random point on them, which shows up as stripes at flat angles.
vec2 waterGradient(vec2 p, float t, int octaves, float footprint) {
	vec2 gradient = vec2(0.0);
	float weight = 1.0;
	float frequency = 0.62;
	float angle = 0.8;
	float speed = 1.15;
	for (int i = 0; i < octaves; i++) {
		vec2 d = vec2(cos(angle), sin(angle));
		float phase = dot(d, p) * frequency + t * speed;
		float s = sin(phase);
		float c = cos(phase);
		float e = exp(s - 1.0);
		float resolved = 1.0 - smoothstep(0.35, 1.25, frequency * footprint);
		gradient += d * e * c * frequency * weight * resolved;
		p -= d * e * c * weight * 0.32;
		weight *= 0.80;
		frequency *= 1.28;
		speed *= 1.06;
		angle += GOLDEN_ANGLE;
	}
	return gradient;
}

// World space normal of the water surface.
vec3 waterNormal(vec3 worldPos, float dist, float footprint) {
#ifdef WATER_WAVES
	float t = frameTimeCounter * float(WATER_WAVE_SPEED) / 100.0;
	float scale = float(WATER_WAVE_HEIGHT) / 100.0 * 0.045;
	float fade = 1.0 / (1.0 + dist * 0.018);
	int octaves = max(3, int(float(WATER_WAVE_OCTAVES) * mix(0.45, 1.0, fade) + 0.5));
	vec2 gradient = waterGradient(worldPos.xz, t, octaves, footprint) * scale * (1.0 + rainStrength * 0.6) * mix(0.35, 1.0, fade);
	return normalize(vec3(-gradient.x, 1.0, -gradient.y));
#else
	return vec3(0.0, 1.0, 0.0);
#endif
}

// Focused light under the surface from the local curvature of the waves.
float waterCaustics(vec2 p) {
#ifdef WATER_WAVES
	float t = frameTimeCounter * float(WATER_WAVE_SPEED) / 100.0;
	const float e = 0.09;
	vec2 gx0 = waterGradient(p - vec2(e, 0.0), t, 5, 0.0);
	vec2 gx1 = waterGradient(p + vec2(e, 0.0), t, 5, 0.0);
	vec2 gy0 = waterGradient(p - vec2(0.0, e), t, 5, 0.0);
	vec2 gy1 = waterGradient(p + vec2(0.0, e), t, 5, 0.0);
	float divergence = ((gx1.x - gx0.x) + (gy1.y - gy0.y)) / (2.0 * e);
	float focus = 1.0 - divergence * 0.34;
	return clamp(focus * focus * 0.5, 0.0, 1.0);
#else
	return 0.5;
#endif
}

vec3 waterAbsorption() {
	return vec3(0.34, 0.075, 0.035) * float(WATER_ABSORPTION) / 100.0;
}

// Light seen through a stretch of water.
vec3 waterVolume(vec3 background, float dist, vec3 ambient, vec3 light) {
	vec3 sigma = waterAbsorption();
	vec3 transmittance = exp(-sigma * dist);
	vec3 inScatter = vec3(0.012, 0.058, 0.076) * (ambient * 1.3 + light * 0.14);
	return background * transmittance + inScatter * (vec3(1.0) - transmittance);
}

#endif
