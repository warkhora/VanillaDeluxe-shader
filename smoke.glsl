// VanillaDeluxe - volumetric smoke above torches, fires and lava.
// Torches and fires come from the light list of the voxel scene. A ray walks through the
// 8 x 8 x 8 cells it crosses, and each smoking source in them adds its plume where the ray passes
// closest to it. Every plume is integrated along that short stretch with a few samples, so thin
// wisps above a torch stay smooth instead of being hit or missed by a coarse march.
// Lava gives off a low haze instead, read straight from the lava blocks in the voxel scene. That
// does not depend on the light list, whose contents change when it overflows above a large lake.
// Requires rt_light.glsl and the global sampler noisetex.
#ifndef VD_SMOKE_INCLUDED
#define VD_SMOKE_INCLUDED 1

struct SmokeSource {
	float base;     // height of the first smoke above the centre of the block
	float height;   // how high the plume rises before it has thinned out
	float radius;   // width at the base
	float spread;   // widening per block of height
	float strength; // density at the base
};

bool smokeSource(uint colorIndex, out SmokeSource s) {
	s = SmokeSource(0.0, 0.0, 0.0, 0.0, 0.0);
	if (colorIndex == RT_COLOR_TORCH || colorIndex == RT_COLOR_SOUL_TORCH) {
		s = SmokeSource(0.25, 3.6, 0.06, 0.14, 4.0);
	} else if (colorIndex == RT_COLOR_FIRE || colorIndex == RT_COLOR_SOUL_FIRE) {
		s = SmokeSource(0.25, 8.0, 0.22, 0.22, 2.6);
	} else {
		return false;
	}
	return true;
}

// The world position of a point in grid coordinates. Patterns are placed in the world, so they
// stay put while the grid moves along with the player.
vec3 smokeWorld(vec3 gridPos) {
	return gridPos - vec3(RT_GRID_CENTER) - cameraPositionFract + cameraPosition;
}

// Density of one plume at a point relative to the centre of its source block.
float plumeDensity(vec3 rel, SmokeSource s, float seed) {
	float h = rel.y - s.base;
	if (h <= 0.0 || h >= s.height) return 0.0;
	float t = frameTimeCounter;
	// The plume leans with a slow breeze and sways more the higher it gets.
	vec2 sway = vec2(sin(t * 0.83 + h * 1.4 + seed), cos(t * 0.67 + h * 1.1 + seed * 1.7)) * 0.09 * h;
	sway += vec2(0.11, 0.05) * h * h / s.height;
	vec2 d = rel.xz - sway;
	float radius = s.radius + s.spread * h;
	float radial = exp(-dot(d, d) / (radius * radius));
	if (radial < 0.01) return 0.0;
	// Rising curls, from the noise texture scrolled upwards.
	vec2 uv = vec2(d.x + d.y * 0.6 + seed * 0.37, h - t * 0.9) * vec2(0.42, 0.21);
	float curl = texture(noisetex, uv).r * 0.65 + texture(noisetex, uv * 2.3 + seed).g * 0.35;
	float fade = smoothstep(0.0, 0.35, h) * pow(1.0 - h / s.height, 1.5);
	// The same amount of smoke spread over a wider plume is thinner.
	float spreadOut = (s.radius + 0.15) / (radius + 0.15);
	return s.strength * radial * fade * spreadOut * spreadOut * smoothstep(0.15, 0.7, curl);
}

const float LAVA_HAZE_HEIGHT = 2.6;

// Haze above lava at a point in grid coordinates, and its height above the lava surface. The
// point looks down through at most three blocks for lava, and stops at anything solid.
float lavaHazeDensity(vec3 gridPos, vec3 offset, out float height) {
	height = 0.0;
	// Only the lookup of the blocks moves sideways. The noise stays in place, or the offset would
	// sweep the pattern back and forth across the whole lake.
	ivec3 c = ivec3(floor(gridPos + offset));
	if (any(lessThan(c, ivec3(0, 3, 0))) || any(greaterThanEqual(c, RT_GRID_SIZE))) return 0.0;
	for (int k = 0; k <= 3; k++) {
		uint v = texelFetch(rtVoxelSampler, c - ivec3(0, k, 0), 0).r;
		if ((v & RT_BIT_LAVA) != 0u) {
			height = gridPos.y - (float(c.y - k) + 0.9);
			if (height <= 0.0 || height >= LAVA_HAZE_HEIGHT) return 0.0;
			vec3 w = smokeWorld(gridPos);
			float t = frameTimeCounter;
			// Two layers of noise that rise and drift slowly, so the haze curls upwards.
			vec2 uv = vec2(w.x * 0.21 + w.z * 0.07, w.z * 0.21 - w.x * 0.05) + vec2(0.0, -(w.y - t * 0.55) * 0.13);
			float curl = texture(noisetex, uv).r * 0.6 + texture(noisetex, uv * 2.4 + vec2(0.31, t * 0.011)).g * 0.4;
			float profile = smoothstep(0.0, 0.25, height) * exp(-height * 1.3);
			return 0.85 * profile * smoothstep(0.2, 0.75, curl);
		}
		if ((v & (RT_BIT_SOLID | RT_BIT_PARTIAL)) != 0u) return 0.0;
	}
	return 0.0;
}

// Smoke in front of a surface: rgb is the light it adds, a how much of the scene still shows.
// feetDir is the normalised view ray in feet space, maxDist the distance to the surface.
// dither moves the samples along the ray, jitter moves the lava samples sideways by up to half a
// block. Both repeat after a few frames, so the temporal filter turns them into a smooth result.
vec4 marchSmoke(vec3 feetDir, float maxDist, vec3 ambient, float dither, vec2 jitter) {
	const float SMOKE_RANGE = 40.0;
	const float LAVA_RANGE = 32.0;
	float range = min(maxDist, SMOKE_RANGE);
	vec3 origin = cameraPositionFract + vec3(RT_GRID_CENTER);
	vec3 safeDir = vec3(abs(feetDir.x) < 1e-4 ? 1e-4 : feetDir.x, abs(feetDir.y) < 1e-4 ? 1e-4 : feetDir.y, abs(feetDir.z) < 1e-4 ? 1e-4 : feetDir.z);
	vec3 invDir = 1.0 / safeDir;
	vec2 horizontal = feetDir.xz;
	float horizontalSq = max(dot(horizontal, horizontal), 1e-4);
	vec3 lavaGlow = rtLightColor(RT_COLOR_LAVA);
	vec3 lavaOffset = vec3(jitter.x - 0.5, 0.0, jitter.y - 0.5);

	vec3 light = vec3(0.0);
	float transmittance = 1.0;
	float t = 0.0;
	for (int c = 0; c < 16 && t < range; c++) {
		vec3 p = origin + feetDir * (t + 1e-3);
		ivec3 cell = ivec3(floor(p)) >> 3;
		vec3 tExit3 = (vec3(cell * 8) + step(vec3(0.0), safeDir) * 8.0 - origin) * invDir;
		float tExit = min(min(tExit3.x, min(tExit3.y, tExit3.z)), range);
		if (all(greaterThanEqual(cell, ivec3(0))) && all(lessThan(cell, RT_CELLS))) {
			ivec3 base = ivec3(cell.x * RT_CELL_TEXELS, cell.y, cell.z);
			int count = rtCellCount(base);
			for (int i = 0; i < count; i++) {
				uint entry = texelFetch(rtLightSampler, base + ivec3(1 + i, 0, 0), 0).r;
				SmokeSource s;
				if (!smokeSource(rtEntryColor(entry), s)) continue;
				vec3 center = vec3(rtEntryCell(entry)) + 0.5;
				// Where the ray passes closest to the axis of the plume. Only the cell that holds
				// that point counts the plume, since a source is listed in several cells.
				vec2 toAxis = center.xz - origin.xz;
				float tClosest = clamp(dot(toAxis, horizontal) / horizontalSq, 0.0, range);
				vec3 closest = origin + feetDir * tClosest;
				if (any(notEqual(ivec3(floor(closest)) >> 3, cell))) continue;
				float reach = s.radius + s.spread * s.height + 0.5;
				vec2 offAxis = closest.xz - center.xz;
				if (dot(offAxis, offAxis) > reach * reach) continue;
				// Integrate across the plume with a few samples around the closest point.
				float halfWidth = min(reach / sqrt(horizontalSq), s.height + 1.0);
				float t0 = max(tClosest - halfWidth, 0.0);
				float t1 = min(tClosest + halfWidth, range);
				if (t1 <= t0) continue;
				float dt = (t1 - t0) / 6.0;
				float seed = fract(dot(smokeWorld(center), vec3(0.137, 0.611, 0.293))) * 40.0;
				vec3 glow = rtLightColor(rtEntryColor(entry));
				for (int k = 0; k < 6; k++) {
					float ts = t0 + (float(k) + dither) * dt;
					vec3 rel = origin + feetDir * ts - center;
					float density = plumeDensity(rel, s, seed) * dt * 1.6;
					if (density <= 0.0) continue;
					// Grey smoke, lit warmly by its own source near the bottom of the plume.
					float h = rel.y - s.base;
					vec3 lit = ambient + glow * 0.9 * exp(-h * 1.1);
					light += transmittance * density * 0.8 * lit;
					transmittance *= exp(-density);
				}
			}
			// Haze above lava, in steps of about a block through this cell.
			if (rtCellHasLava(base) && t < LAVA_RANGE) {
				float l0 = t;
				float l1 = min(tExit, LAVA_RANGE);
				int steps = int(clamp(ceil(l1 - l0), 1.0, 10.0));
				float dt = (l1 - l0) / float(steps);
				for (int k = 0; k < steps; k++) {
					float ts = l0 + (float(k) + dither) * dt;
					float h;
					float density = lavaHazeDensity(origin + feetDir * ts, lavaOffset, h) * dt;
					if (density <= 0.0) continue;
					vec3 lit = ambient + lavaGlow * 0.8 * exp(-h * 1.6);
					light += transmittance * density * 0.8 * lit;
					transmittance *= exp(-density);
				}
			}
		}
		t = tExit + 1e-3;
	}
	return vec4(light, transmittance);
}

// True for a point a short way above a smoking source, where vanilla smoke particles rise.
bool nearSmokeSource(vec3 feet) {
	vec3 p = feet + cameraPositionFract + vec3(RT_GRID_CENTER);
	ivec3 cell = ivec3(floor(p)) >> 3;
	if (any(lessThan(cell, ivec3(0))) || any(greaterThanEqual(cell, RT_CELLS))) return false;
	ivec3 base = ivec3(cell.x * RT_CELL_TEXELS, cell.y, cell.z);
	int count = rtCellCount(base);
	for (int i = 0; i < count; i++) {
		uint entry = texelFetch(rtLightSampler, base + ivec3(1 + i, 0, 0), 0).r;
		SmokeSource s;
		if (!smokeSource(rtEntryColor(entry), s)) continue;
		vec3 rel = p - (vec3(rtEntryCell(entry)) + 0.5);
		float reach = 1.2 + s.radius + s.spread * max(rel.y, 0.0);
		if (rel.y > -0.6 && rel.y < s.height + 2.0 && dot(rel.xz, rel.xz) < reach * reach) return true;
	}
	// Above lava: smoke particles rise from it too.
	ivec3 c = ivec3(floor(p));
	for (int k = 1; k <= 3; k++) {
		ivec3 q = c - ivec3(0, k, 0);
		if (any(lessThan(q, ivec3(0))) || any(greaterThanEqual(q, RT_GRID_SIZE))) break;
		uint v = texelFetch(rtVoxelSampler, q, 0).r;
		if ((v & RT_BIT_LAVA) != 0u) return true;
		if ((v & RT_BIT_SOLID) != 0u) break;
	}
	return false;
}

#endif
