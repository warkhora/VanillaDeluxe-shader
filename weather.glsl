// VanillaDeluxe - rain ripples and wind, shared by puddles, water and falling rain and snow.
#ifndef VD_WEATHER_INCLUDED
#define VD_WEATHER_INCLUDED 1

vec2 weatherHash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// One layer of raindrop rings on a grid. Every cell gets one drop at a random place and time.
// Each ring spreads out from its drop and dies away before the next drop in that cell lands.
// Returns the slope of the surface, so it gives a normal without finite differences.
vec2 rippleLayer(vec2 p, float t, float cellSize, float rate) {
	vec2 cellPos = p / cellSize;
	vec2 cell = floor(cellPos);
	vec2 random = weatherHash2(cell);
	// The drop lands inside the middle of the cell, so its ring stays inside the cell.
	vec2 center = cell + 0.35 + random * 0.3;
	float age = fract(t * rate + random.x * 7.13 + random.y * 3.71);
	vec2 toCenter = cellPos - center;
	float dist = length(toCenter);
	float radius = age * 0.32;
	float x = (dist - radius) * 34.0;
	// A short wave train behind the front, fading as the ring grows.
	float envelope = exp(-x * x * 0.08) * (1.0 - age) * (1.0 - age);
	float slope = cos(x) * envelope * 34.0 / cellSize;
	return dist > 1e-4 ? toCenter / dist * slope : vec2(0.0);
}

// Rain ripples on a horizontal surface. Layers of rings at different sizes and speeds, fewer
// with lower quality. They fade with distance, where they are smaller than a pixel.
vec2 rainRipples(vec2 worldXZ, float dist) {
	vec2 slope = vec2(0.0);
#if WEATHER_SPLASH_QUALITY > 0
	float fade = 1.0 - smoothstep(10.0, 28.0, dist);
	if (fade <= 0.0) return slope;
	float t = frameTimeCounter;
	slope += rippleLayer(worldXZ, t, 0.62, 1.30);
#if WEATHER_SPLASH_QUALITY > 1
	slope += rippleLayer(worldXZ + vec2(0.31, 0.17), t + 0.37, 0.41, 1.65) * 0.8;
#endif
#if WEATHER_SPLASH_QUALITY > 2
	slope += rippleLayer(worldXZ + vec2(0.73, 0.52), t + 0.71, 0.29, 2.10) * 0.6;
	slope += rippleLayer(worldXZ + vec2(0.11, 0.88), t + 0.19, 0.83, 1.05) * 0.7;
#endif
	slope *= 0.0045 * fade;
#endif
	return slope;
}

// Direction the weather blows towards. It turns slowly, and gusts come and go.
vec2 weatherWindDirection() {
	float angle = 0.35 + 0.25 * sin(frameTimeCounter * 0.021);
	return vec2(cos(angle), sin(angle));
}
float weatherGust(vec3 worldPos) {
	return 0.65 + 0.35 * sin(frameTimeCounter * 0.53 + worldPos.x * 0.031 + worldPos.z * 0.027);
}

// ---- Weather on glass --------------------------------------------------------
// p is a point on the pane in blocks: across the pane, and up. All drops are small lenses, so
// they return the slope of the water surface, which bends the view and the reflections.

// Slope of a drop of the given radius at offset d from its centre, flattened towards its edge.
vec2 dropSlope(vec2 d, float radius) {
	float r2 = dot(d, d) / (radius * radius);
	if (r2 >= 1.0) return vec2(0.0);
	float h = sqrt(1.0 - r2);
	return d / (radius * max(h, 0.25)) * 0.55;
}

// Rain on a window: beads that sit on the glass, grow and dry up again, and larger drops that
// run down in their own lanes and leave a trail of beads behind them.
vec2 glassRaindrops(vec2 p, float t) {
	vec2 slope = vec2(0.0);
	// Beads, in two sizes.
	for (int layer = 0; layer < 2; layer++) {
		float size = layer == 0 ? 0.075 : 0.045;
		vec2 cellPos = p / size + float(layer) * vec2(0.37, 0.71);
		vec2 cell = floor(cellPos);
		vec2 random = weatherHash2(cell + float(layer) * 31.7);
		if (random.x < 0.45) continue;
		float life = fract(t * (0.05 + 0.06 * random.y) + random.x * 4.7);
		float grow = smoothstep(0.0, 0.25, life) * (1.0 - smoothstep(0.75, 1.0, life));
		vec2 center = cell + 0.3 + 0.4 * weatherHash2(cell + 9.1);
		slope += dropSlope((cellPos - center) * size, size * (0.16 + 0.16 * random.y) * grow);
	}
	// Running drops, one per lane. They move in fits and starts, as real drops stick and slip.
	float laneWidth = 0.21;
	float lane = floor(p.x / laneWidth);
	vec2 laneRandom = weatherHash2(vec2(lane, 13.7));
	if (laneRandom.x > 0.35) {
		float speed = 0.18 + 0.32 * laneRandom.y;
		float progress = t * speed + laneRandom.x * 9.0;
		progress += 0.15 * sin(t * (1.3 + laneRandom.y) + lane);
		float span = 1.7;
		float head = span - fract(progress / span) * span; // height of the drop within its span
		float local = mod(p.y, span);
		float x = (fract(p.x / laneWidth) - 0.5 - 0.18 * sin(p.y * 7.0 + lane * 3.1)) * laneWidth;
		// The head of the drop.
		slope += dropSlope(vec2(x, (local - head) * 0.55), 0.028);
		// Its trail: a thin film above the head, broken into beads.
		float above = local - head;
		if (above > 0.0 && above < 0.6) {
			float bead = fract(above * 9.0);
			float trail = (1.0 - above / 0.6) * smoothstep(0.012, 0.0, abs(x));
			slope += dropSlope(vec2(x, (bead - 0.5) / 9.0), 0.012) * trail;
		}
	}
	return slope;
}

// Frost that grows in from the edges of each pane while it snows. amount is 0 to 1.
float glassFrost(vec2 p, float amount) {
	if (amount <= 0.0) return 0.0;
	vec2 f = fract(p);
	float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
	// Crystals: a hashed pattern on a fine grid, so the frost line is ragged instead of straight.
	vec2 fine = floor(p * 96.0);
	float crystal = weatherHash2(fine).x * 0.6 + weatherHash2(floor(p * 13.0) + 4.0).y * 0.4;
	float reach = 0.025 + 0.085 * amount;
	// More frost gathers along the bottom of the pane, where snow settles.
	reach *= mix(1.0, 1.8, 1.0 - smoothstep(0.0, 0.3, f.y));
	return smoothstep(reach, reach * 0.35, edge - crystal * 0.05) * (0.55 + 0.45 * crystal) * amount;
}


#endif
