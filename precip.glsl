// VanillaDeluxe - procedural snowfall and rain splashes, drawn into the finished image.
// Both are fields of small particles fixed in the world, so they have real depth and parallax.
// A particle is drawn as a soft disc. Below the size of a pixel it is spread over a pixel with
// the same total brightness, which keeps distant snow an even, soft haze instead of flickering.
// Every particle checks the weather map, so none falls under a roof. Requires common.glsl,
// weather.glsl and weather_map.glsl.
#ifndef VD_PRECIP_INCLUDED
#define VD_PRECIP_INCLUDED 1

vec4 precipHash4(vec3 p) {
	vec4 q = vec4(dot(p, vec3(127.1, 311.7, 74.7)), dot(p, vec3(269.5, 183.3, 246.1)),
		dot(p, vec3(113.5, 271.9, 124.6)), dot(p, vec3(201.3, 87.1, 173.9)));
	return fract(sin(q) * 43758.5453);
}

// Coverage of a particle of the given radius whose centre lies offAxis blocks from the ray, seen
// at distance dist. pixelAngle is the angle of one pixel.
float particleCoverage(float offAxis, float radius, float dist, float pixelAngle) {
	float pixel = pixelAngle * dist;
	float soft = max(radius, pixel * 0.8);
	float energy = (radius * radius) / (soft * soft);
	return energy * (1.0 - smoothstep(soft * 0.35, soft, offAxis));
}

// ---- Snow --------------------------------------------------------------------
// Layers of flakes at growing distances. Each layer is its own field of cells. A pixel looks at
// the cells around the point where its ray crosses the layer, and finds the flake in each.
// Returns the light of the flakes in rgb and their coverage in a.
vec4 snowField(vec3 dir, float sceneDist, float nearest, float pixelAngle, float intensity, out vec3 flakeFeet) {
	flakeFeet = vec3(0.0);
#if SNOW_QUALITY > 1
	const int LAYERS = 10;
#else
	const int LAYERS = 6;
#endif
	float t = frameTimeCounter;
	vec2 wind = weatherWindDirection() * float(SNOW_WIND_DRIFT) / 100.0;
	// The whole field falls and drifts with the wind.
	vec3 motion = vec3(wind.x * 0.9, -1.1, wind.y * 0.9) * t;
	float coverage = 0.0;
	float nearestFlake = 1e5;
	for (int i = LAYERS - 1; i >= 0; i--) {
		float d = 1.1 * pow(1.5, float(i));
		if (d >= sceneDist || d < nearest) continue;
		// Cells grow with distance, so every layer holds about as many flakes on screen.
		float size = 0.17 + d * 0.05;
		float density = intensity * mix(0.55, 0.30, float(i) / float(LAYERS));
		for (int k = -1; k <= 1; k++) {
			vec3 p = dir * (d + float(k) * size * 0.5) + cameraPosition;
			vec3 q = (p - motion) / size + float(i) * 17.31;
			vec3 cell = floor(q);
			// The same cell can come up for two of the three points. Count it once.
			if (k > -1) {
				vec3 previous = floor((dir * (d + float(k - 1) * size * 0.5) + cameraPosition - motion) / size + float(i) * 17.31);
				if (all(equal(previous, cell))) continue;
			}
			vec4 random = precipHash4(cell);
			if (random.w > density) continue;
			// Each flake also swirls on its own path.
			vec3 swirl = vec3(sin(t * (0.9 + random.x) + random.y * 6.28), 0.0, cos(t * (0.8 + random.y) + random.x * 6.28)) * 0.12;
			vec3 center = (cell + 0.25 + 0.5 * random.xyz + float(i) * -17.31) * size + motion + swirl * size;
			vec3 toCenter = center - cameraPosition;
			float along = dot(toCenter, dir);
			if (along <= 0.05 || along >= sceneDist) continue;
#ifdef USE_WEATHER_MAP
			if (weatherReachPoint(toCenter) < 0.5) continue;
#endif
			float offAxis = length(toCenter - dir * along);
			float radius = 0.014 + 0.012 * random.x;
			// Only the stretch of this layer counts, faded at its ends so no flake pops.
			float inLayer = 1.0 - smoothstep(size * 0.3, size * 0.5, abs(along - d));
			float c = particleCoverage(offAxis, radius, along, pixelAngle) * inLayer;
			if (c <= 0.0) continue;
			coverage = coverage + c * (1.0 - coverage);
			if (along < nearestFlake) {
				nearestFlake = along;
				flakeFeet = toCenter;
			}
		}
	}
	return vec4(vec3(0.0), saturate(coverage));
}

// ---- Rain splashes -------------------------------------------------------------
// Where a drop hits the ground, a few tiny droplets jump up and fall back. The view ray is
// followed back from the ground through the thin layer just above it, and each point on it looks
// for a splash in its cell of the ground. Height and number grow with the strength of the rain.
float splashField(vec3 dir, vec3 groundFeet, float dist, float pixelAngle, float strength) {
	float t = frameTimeCounter;
	float height = 0.10 + 0.16 * strength;
	float descend = max(-dir.y, 0.2);
	vec3 ground = groundFeet + cameraPosition;
	float coverage = 0.0;
	const float CELL = 0.24;
	for (int k = 0; k < 3; k++) {
		vec3 p = ground - dir * (height * (float(k) + 0.5) / 3.0 / descend);
		vec2 cell = floor(p.xz / CELL);
		vec4 random = precipHash4(vec3(cell, 3.7));
		// Stronger rain: more of the cells have a splash going.
		if (random.w > 0.25 + 0.55 * strength) continue;
		float age = fract(t * (1.6 + 0.8 * random.z) + random.x * 5.3);
		float flight = 0.45;
		if (age > flight) continue;
		float tau = age / flight;
		vec2 impact = (cell + 0.2 + 0.6 * random.xy) * CELL;
		for (int m = 0; m < 3; m++) {
			float angle = (float(m) + random.z) * 2.094;
			vec2 out2 = vec2(cos(angle), sin(angle)) * tau * (0.05 + 0.04 * random.y);
			float peak = height * (0.55 + 0.45 * fract(random.y * 7.0 + float(m) * 0.31));
			vec3 droplet = vec3(impact.x + out2.x, ground.y + 4.0 * peak * tau * (1.0 - tau), impact.y + out2.y);
			vec3 toDrop = droplet - cameraPosition;
			float along = dot(toDrop, dir);
			if (along <= 0.05) continue;
			float offAxis = length(toDrop - dir * along);
			float c = particleCoverage(offAxis, 0.010, along, pixelAngle) * (1.0 - tau * 0.5);
			coverage = coverage + c * (1.0 - coverage);
		}
	}
	return saturate(coverage) * (1.0 - smoothstep(9.0, 15.0, dist));
}

#endif
