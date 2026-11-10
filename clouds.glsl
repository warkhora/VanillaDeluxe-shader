// VanillaDeluxe - volumetric cloud layer raymarched at half resolution.
// Requires: common.glsl and a declared noisetex sampler.
#ifndef VD_CLOUDS_INCLUDED
#define VD_CLOUDS_INCLUDED 1

const float CLOUD_BASE = float(CLOUD_ALTITUDE);
const float CLOUD_TOP = float(CLOUD_ALTITUDE) + float(CLOUD_THICKNESS);
const float CLOUD_MAX_DISTANCE = 6000.0;

// Value noise with a smoothed lookup. One unit is one cell of the noise texture.
float cloudNoise2D(vec2 p) {
	vec2 i = floor(p);
	vec2 f = p - i;
	f = f * f * (3.0 - 2.0 * f);
	return texture(noisetex, (i + f + 0.5) / 256.0).r;
}
float cloudNoise3D(vec3 p) {
	float slice = floor(p.y);
	float f = p.y - slice;
	f = f * f * (3.0 - 2.0 * f);
	vec2 a = p.xz + slice * vec2(37.0, 17.0);
	float n0 = cloudNoise2D(a);
	float n1 = cloudNoise2D(a + vec2(37.0, 17.0));
	return mix(n0, n1, f);
}

vec2 cloudWind() {
	return vec2(frameTimeCounter * 3.2, frameTimeCounter * 1.1) * float(CLOUD_SPEED) / 100.0;
}

float cloudCoverage() {
	// Rain closes the cloud cover, and a thunderstorm closes it almost completely.
	return float(CLOUD_COVERAGE) / 100.0 + rainStrength * 0.32 + thunderStrength * 0.18;
}

// Large scale shape only. Good enough for shadows and reflections.
float cloudShape(vec2 xz) {
	const mat2 rot = mat2(0.80, 0.60, -0.60, 0.80);
	vec2 p = (xz + cloudWind()) * 0.00165;
	float n = cloudNoise2D(p) * 0.56;
	p = rot * p * 2.3 + 3.1;
	n += cloudNoise2D(p) * 0.29;
	p = rot * p * 2.4 + 7.7;
	n += cloudNoise2D(p) * 0.15;
	float threshold = 1.0 - cloudCoverage();
	return saturate((n - threshold) / 0.22);
}

float cloudDensity(vec3 worldPos, bool detailed) {
	float h = (worldPos.y - CLOUD_BASE) / (CLOUD_TOP - CLOUD_BASE);
	if (h <= 0.0 || h >= 1.0) return 0.0;
	float shape = cloudShape(worldPos.xz);
	if (shape <= 0.0) return 0.0;
	// The thicker the cloud is at this spot, the higher it rises: flat base, domed top.
	float top = 0.15 + 0.85 * sqrt(shape);
	float d = smoothstep(0.0, 0.08, h) * smoothstep(top, top * 0.62, h);
	if (d <= 0.0) return 0.0;
	if (detailed) {
		vec3 q = worldPos + vec3(cloudWind().x, 0.0, cloudWind().y);
		float erode = cloudNoise3D(q * 0.024) * 0.62 + cloudNoise3D(q * 0.071 + 11.0) * 0.38;
		// Erosion bites hardest where the cloud is thin, which frays the edges.
		d = saturate((d * (0.35 + 0.65 * shape) - erode * 0.52) / 0.42);
	}
	return d;
}

// Approximate fraction of sunlight blocked by the cloud layer above a point.
float cloudShadowAt(vec3 worldPos, vec3 lightDir) {
	if (lightDir.y <= 0.02) return 1.0;
	float t = (0.5 * (CLOUD_BASE + CLOUD_TOP) - worldPos.y) / lightDir.y;
	if (t <= 0.0) return 1.0;
	vec3 p = worldPos + lightDir * t;
	float shape = cloudShape(p.xz);
	return 1.0 - 0.78 * smoothstep(0.0, 0.7, shape);
}

// Marches the layer between two distances along a ray starting at rayOrigin.
// Returns in-scattered light (rgb) and transmittance (a).
vec4 marchClouds(vec3 rayOrigin, vec3 dir, float maxDistance, float dither, vec3 lightDir, vec3 lightColor, vec3 ambient) {
	vec4 empty = vec4(0.0, 0.0, 0.0, 1.0);
	if (abs(dir.y) < 1e-4) return empty;
	float tBase = (CLOUD_BASE - rayOrigin.y) / dir.y;
	float tTop = (CLOUD_TOP - rayOrigin.y) / dir.y;
	float tEnter = max(min(tBase, tTop), 0.0);
	float tExit = max(tBase, tTop);
	tExit = min(tExit, min(maxDistance, CLOUD_MAX_DISTANCE));
	if (tExit <= tEnter) return empty;
	// Rays near the horizon cross the layer for kilometres. Spending the budget on the first
	// part keeps the steps short enough to resolve the shapes of the clouds.
	tExit = min(tExit, tEnter + 1500.0);

	float stepLength = (tExit - tEnter) / float(CLOUD_STEPS);
	float cosTheta = dot(dir, lightDir);
	float phase = mix(phaseHG(cosTheta, -0.20), phaseHG(cosTheta, 0.72), 0.55) + 0.05;
	float lightStep = (CLOUD_TOP - CLOUD_BASE) * 0.72 / float(CLOUD_SUN_STEPS);

	vec3 inScatter = vec3(0.0);
	float transmittance = 1.0;
	float t = tEnter + stepLength * dither;
	for (int i = 0; i < CLOUD_STEPS; i++) {
		vec3 p = rayOrigin + dir * t;
		float density = cloudDensity(p, true);
		if (density > 0.004) {
			float opticalToLight = 0.0;
			for (int j = 0; j < CLOUD_SUN_STEPS; j++) {
				vec3 q = p + lightDir * lightStep * (float(j) + 0.5);
				opticalToLight += cloudDensity(q, false);
			}
			opticalToLight *= lightStep * 0.030;
			// Two terms stand in for multiple scattering, which keeps the inside of a cloud lit.
			float beer = 0.70 * exp(-opticalToLight) + 0.42 * exp(-opticalToLight * 0.20);
			float powder = 1.0 - 0.60 * exp(-density * 8.0);
			float h = saturate((p.y - CLOUD_BASE) / (CLOUD_TOP - CLOUD_BASE));
			vec3 sunLight = lightColor * beer * powder * phase * 3.1;
			vec3 skyLight = ambient * mix(0.42, 0.90, h);
			float stepOptical = density * stepLength * 0.045;
			float stepTransmittance = exp(-stepOptical);
			inScatter += transmittance * (sunLight + skyLight) * (1.0 - stepTransmittance);
			transmittance *= stepTransmittance;
			if (transmittance < 0.015) break;
		}
		t += stepLength;
	}
	// Far clouds dissolve into the haze at the horizon.
	float distanceFade = exp(-tEnter * 0.00042);
	return vec4(inScatter * distanceFade, mix(1.0, transmittance, distanceFade));
}

#endif
