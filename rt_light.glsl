// VanillaDeluxe - ray traced block light. Iris gives shaders no access to hardware ray tracing,
// so the shadow pass writes the blocks around the player to a 3D image, and every light source
// to a list for each 8 x 8 x 8 cell it can reach. A pixel then picks one nearby light in
// proportion to what it could contribute, and traces one shadow ray to it through the voxels.
// With one light in reach there is no noise at all, except in the penumbra of its shadows.
#ifndef VD_RT_LIGHT_INCLUDED
#define VD_RT_LIGHT_INCLUDED 1

const ivec3 RT_GRID_SIZE = ivec3(128, 64, 128);
const ivec3 RT_GRID_CENTER = ivec3(64, 32, 64);
const ivec3 RT_CELLS = ivec3(16, 8, 16);
const int RT_CELL_TEXELS = 16;
const uint RT_CELL_CAPACITY = 15u;

// Voxels. Light passes through what has no bit set, like air, water and glass. Tinted glass
// colours the light that passes, which only Advanced Color Tracing records.
const uint RT_BIT_SOLID = 1u;
const uint RT_BIT_PARTIAL = 2u;
const uint RT_BIT_LEAVES = 4u;
const uint RT_BIT_LISTED = 8u;
const uint RT_BIT_TINTED = 16u;
const uint RT_BIT_COLORED = 32u;
// A block of lava. Volumetric smoke rises from these, independent of the light list.
const uint RT_BIT_LAVA = 64u;
// The top bit of the count in a light list records that lava is among its lights.
const uint RT_LIST_LAVA = 0x80000000u;

// Advanced Color Tracing keeps one colour in the top 24 bits of a voxel: the light a source
// gives off, taken from its texture, or the colour that stained glass lets through. It is
// written once, by the first vertex of the block, so the bits never mix. Keeping it in the same
// image also keeps it working for glass, which is drawn after the shadow depth has been copied.
uint rtPackVoxelColor(vec3 color) {
	uvec3 q = uvec3(clamp(color, vec3(0.0), vec3(1.0)) * 255.0 + 0.5);
	return RT_BIT_COLORED | (q.r << 8) | (q.g << 16) | (q.b << 24);
}
vec3 rtVoxelColor(uint v) {
	return vec3(float((v >> 8) & 255u), float((v >> 16) & 255u), float(v >> 24)) / 255.0;
}

// Colours of the light sources, by index.
const uint RT_COLOR_WARM = 0u;
const uint RT_COLOR_FIRE = 1u;
const uint RT_COLOR_LAVA = 2u;
const uint RT_COLOR_GLOW = 3u;
const uint RT_COLOR_SOUL = 4u;
const uint RT_COLOR_COOL = 5u;
const uint RT_COLOR_RED = 6u;
const uint RT_COLOR_PURPLE = 7u;
// Sources that also give off smoke.
const uint RT_COLOR_TORCH = 8u;
const uint RT_COLOR_SOUL_TORCH = 9u;
const uint RT_COLOR_SOUL_FIRE = 10u;

// One list entry: x 7 bits, y 6, z 7, level 4, colour 4, closeness to the cell 4. The closeness
// is on top, so when a list overflows, an atomic maximum keeps the lights nearest to the cell.
uint rtPackLight(ivec3 cell, uint level, uint colorIndex, uint closeness) {
	return uint(cell.x) | (uint(cell.y) << 7) | (uint(cell.z) << 13) | (level << 20) | (colorIndex << 24) | (closeness << 28);
}

#ifndef SHADOW_PASS

uniform usampler3D rtVoxelSampler;
uniform usampler3D rtLightSampler;

// Number of lights in the list that starts at base, and whether lava is among them.
int rtCellCount(ivec3 base) {
	return int(min(texelFetch(rtLightSampler, base, 0).r & ~RT_LIST_LAVA, RT_CELL_CAPACITY));
}
bool rtCellHasLava(ivec3 base) {
	return (texelFetch(rtLightSampler, base, 0).r & RT_LIST_LAVA) != 0u;
}

const int RT_CANDIDATES = 6;
// Brightness of the ray traced light. It replaces the vanilla light map completely, so a lit
// wall has about the brightness it would have had with the light map.
const float RT_LIGHT_SCALE = 2.4;

ivec3 rtEntryCell(uint entry) {
	return ivec3(int(entry & 127u), int((entry >> 7) & 63u), int((entry >> 13) & 127u));
}
uint rtEntryLevel(uint entry) {
	return (entry >> 20) & 15u;
}
uint rtEntryColor(uint entry) {
	return (entry >> 24) & 15u;
}

vec3 rtLightColor(uint index) {
	if (index == RT_COLOR_FIRE) return vec3(1.0, 0.45, 0.14);
	if (index == RT_COLOR_LAVA) return vec3(1.0, 0.34, 0.06) * float(LAVA_EMISSIVE_BRIGHTNESS);
	if (index == RT_COLOR_GLOW) return vec3(1.0, 0.70, 0.36);
	if (index == RT_COLOR_SOUL || index == RT_COLOR_SOUL_TORCH || index == RT_COLOR_SOUL_FIRE) return vec3(0.20, 0.62, 1.0);
	if (index == RT_COLOR_COOL) return vec3(0.62, 0.86, 1.0);
	if (index == RT_COLOR_RED) return vec3(1.0, 0.10, 0.04);
	if (index == RT_COLOR_PURPLE) return vec3(0.62, 0.28, 1.0);
	return vec3(1.0, 0.52, 0.24);
}

// The light leaves lava from just above its surface, and a torch from a small flame.
float rtLightSize(uint index) {
	if (index == RT_COLOR_LAVA) return 1.4;
	if (index == RT_COLOR_GLOW || index == RT_COLOR_COOL) return 0.7;
	if (index == RT_COLOR_FIRE || index == RT_COLOR_SOUL_FIRE) return 0.5;
	return 0.22;
}
vec3 rtLightCenter(uint entry) {
	vec3 center = vec3(rtEntryCell(entry)) + 0.5;
	if (rtEntryColor(entry) == RT_COLOR_LAVA) center.y += 0.4;
	return center;
}

// The voxel scene is complete close to the player, and fades out towards its edge.
float rtRangeFade(vec3 feet) {
	float across = max(abs(feet.x), abs(feet.z));
	return (1.0 - smoothstep(42.0, 54.0, across)) * (1.0 - smoothstep(13.0, 22.0, abs(feet.y)));
}

// How much of the vanilla light map stays on top of the ray traced light. The standard is none,
// which leaves shadows of block light as dark as if the light were not there. Pixels that no
// listed light reaches, like those beyond the voxel scene, keep all of it.
float rtLightmapScale(vec3 feet) {
	float fade = rtRangeFade(feet);
	if (fade <= 0.0) return 1.0;
	ivec3 cell = (ivec3(floor(feet + cameraPositionFract)) + RT_GRID_CENTER) >> 3;
	if (any(lessThan(cell, ivec3(0))) || any(greaterThanEqual(cell, RT_CELLS))) return 1.0;
	if ((texelFetch(rtLightSampler, ivec3(cell.x * RT_CELL_TEXELS, cell.y, cell.z), 0).r & ~RT_LIST_LAVA) == 0u) return 1.0;
	return mix(1.0, float(RT_LIGHT_FILL) / 100.0, fade);
}

// Steps through the voxels from origin to target, both in grid coordinates. The first and last
// cell do not count: they hold the surface the ray leaves and the light it is looking for.
// Returns the light that gets through, which stained glass can colour.
vec3 rtShadowRay(vec3 origin, vec3 target) {
	vec3 dir = target - origin;
	vec3 safeDir = vec3(abs(dir.x) < 1e-4 ? 1e-4 : dir.x, abs(dir.y) < 1e-4 ? 1e-4 : dir.y, abs(dir.z) < 1e-4 ? 1e-4 : dir.z);
	vec3 invDir = 1.0 / safeDir;
	ivec3 cell = ivec3(floor(origin));
	ivec3 last = ivec3(floor(target));
	ivec3 stepDir = ivec3(sign(safeDir));
	vec3 tDelta = abs(invDir);
	vec3 tNext = (vec3(cell) + step(vec3(0.0), safeDir) - origin) * invDir;
	vec3 visibility = vec3(1.0);
	float rayLength = length(dir);
	for (int i = 0; i < 48; i++) {
		float t;
		if (tNext.x < tNext.y && tNext.x < tNext.z) {
			t = tNext.x;
			tNext.x += tDelta.x;
			cell.x += stepDir.x;
		} else if (tNext.y < tNext.z) {
			t = tNext.y;
			tNext.y += tDelta.y;
			cell.y += stepDir.y;
		} else {
			t = tNext.z;
			tNext.z += tDelta.z;
			cell.z += stepDir.z;
		}
		if (t >= 1.0 || all(equal(cell, last))) break;
		if (any(lessThan(cell, ivec3(0))) || any(greaterThanEqual(cell, RT_GRID_SIZE))) break;
		// The ray spends from t until the next crossing in this cell.
		float tExit = min(min(tNext.x, min(tNext.y, tNext.z)), 1.0);
		uint voxel = texelFetch(rtVoxelSampler, cell, 0).r;
		// Stairs, slabs and leaves fill part of their cell, so they dim the light instead of
		// stopping it. Being exact here would cost another ray, and the denoiser would blur it.
		if ((voxel & RT_BIT_PARTIAL) != 0u) visibility *= 0.6;
		else if ((voxel & RT_BIT_SOLID) != 0u) return vec3(0.0);
		else if ((voxel & RT_BIT_LEAVES) != 0u) visibility *= 0.55;
#ifdef USE_COLOR_TRACING
		// Stained glass filters in proportion to the distance the light travels through it, so
		// a ray that only clips the corner of a pane takes on little of its colour.
		else if ((voxel & RT_BIT_TINTED) != 0u) {
			vec3 tint = (voxel & RT_BIT_COLORED) != 0u ? max(rtVoxelColor(voxel), vec3(0.01)) : vec3(1.0);
			visibility *= pow(tint, vec3(clamp((tExit - t) * rayLength, 0.0, 1.8)));
		}
#endif
	}
	return visibility;
}

// Light arriving at a point from the block light sources around it. Brightness over distance
// starts from the same curve as the vanilla light level, so that levels and settings carry over.
// Without a shadow ray the light only stops where the vanilla light level ends. The bounce light
// uses that for its deeper bounces, where a shadow would hardly show.
vec3 rtBlockLight(vec3 feet, vec3 N, bool twoSided, vec4 random, bool shadowed) {
	float fade = rtRangeFade(feet);
	if (fade <= 0.0) return vec3(0.0);
	vec3 position = feet + N * 0.06 + cameraPositionFract + vec3(RT_GRID_CENTER);
	ivec3 cell = ivec3(floor(position)) >> 3;
	if (any(lessThan(cell, ivec3(0))) || any(greaterThanEqual(cell, RT_CELLS))) return vec3(0.0);
	ivec3 base = ivec3(cell.x * RT_CELL_TEXELS, cell.y, cell.z);
	int count = rtCellCount(base);
	if (count == 0) return vec3(0.0);

	int tested = min(count, RT_CANDIDATES);
	int first = tested < count ? int(random.w * float(count)) : 0;
	uint entries[RT_CANDIDATES];
	float weights[RT_CANDIDATES];
	float total = 0.0;
	for (int i = 0; i < tested; i++) {
		uint entry = texelFetch(rtLightSampler, base + ivec3(1 + (first + i) % count, 0, 0), 0).r;
		entries[i] = entry;
		weights[i] = 0.0;
		vec3 toLight = rtLightCenter(entry) - position;
		float dist = length(toLight);
		float reach = (float(rtEntryLevel(entry)) - dist) / 15.0;
		if (reach <= 0.0) continue;
		float cosine = dot(N, toLight) / max(dist, 1e-3);
		if (twoSided) cosine = 0.6 + 0.4 * abs(cosine);
		if (cosine <= 0.0) continue;
		// Light thins out with distance as well, which gives each source its own pool of light.
		float strength = reach * reach * (0.22 + 1.05 * reach * reach) / (1.0 + dist * dist * 0.06);
		// One listed block of lava stands in for the blocks around it, and they add up quickly.
		if (rtEntryColor(entry) == RT_COLOR_LAVA) strength *= 0.4;
		weights[i] = strength * cosine;
		total += weights[i];
	}
	if (total <= 0.0) return vec3(0.0);

	int chosen = 0;
	float pick = random.x * total;
	for (int i = 0; i < tested; i++) {
		if (weights[i] <= 0.0) continue;
		chosen = i;
		pick -= weights[i];
		if (pick <= 0.0) break;
	}
	uint entry = entries[chosen];
	uint colorIndex = rtEntryColor(entry);
	vec3 visibility = vec3(1.0);
	if (shadowed) {
		vec3 target = rtLightCenter(entry) + (random.yzw - 0.5) * rtLightSize(colorIndex);
		visibility = rtShadowRay(position, target);
		if (max(visibility.r, max(visibility.g, visibility.b)) <= 0.0) return vec3(0.0);
	}

	vec3 color = rtLightColor(colorIndex);
#ifdef USE_COLOR_TRACING
	uint lightVoxel = texelFetch(rtVoxelSampler, rtEntryCell(entry), 0).r;
	// Lava is listed for a patch of blocks, at a block that may hold something else.
	if (colorIndex != RT_COLOR_LAVA && (lightVoxel & RT_BIT_COLORED) != 0u) {
		color = rtVoxelColor(lightVoxel);
		if (colorIndex == RT_COLOR_LAVA) color *= float(LAVA_EMISSIVE_BRIGHTNESS);
	}
#endif

	// Many blocks of lava together must not add up to many suns.
	total *= float(count) / float(tested);
	float energy = total / (1.0 + total * 0.5);
	return color * energy * visibility * fade * RT_LIGHT_SCALE * float(BLOCKLIGHT_STRENGTH) / 100.0;
}

#endif
#endif
