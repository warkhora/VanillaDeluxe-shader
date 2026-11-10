// VanillaDeluxe - the weather map: the highest block in every column within 64 blocks of the
// player, written by the shadow pass. It tells for any point whether rain and snow can reach it,
// the same way the game decides where precipitation falls, so nothing under a roof gets wet,
// splashed or snowed on. It also shows dips in the ground, where puddles gather first.
#ifndef VD_WEATHER_MAP_INCLUDED
#define VD_WEATHER_MAP_INCLUDED 1

// Same layout as the voxel scene: column 64, 64 is the one the camera stands in. Heights are
// stored relative to the camera, offset so that they are always positive.
const ivec3 WM_CENTER = ivec3(64, 32, 64);
const int WM_SIZE = 128;
const int WM_OFFSET = 1024;

#if defined USE_WEATHER_MAP && !defined SHADOW_PASS
uniform usampler2D rtHeightSampler;

// The cell of a point relative to the map, in x, y and z.
ivec3 weatherCell(vec3 feet) {
	return ivec3(floor(feet + cameraPositionFract)) + WM_CENTER;
}
// Height of the highest block in a column, or none when nothing in it stops rain.
bool weatherColumnTop(ivec2 column, out int top) {
	uint stored = texelFetch(rtHeightSampler, column, 0).r;
	top = int(stored) - WM_OFFSET;
	return stored != 0u;
}
float weatherColumnOpen(ivec2 column, int y) {
	int top;
	return weatherColumnTop(column, top) && y <= top ? 0.0 : 1.0;
}
bool weatherInMap(ivec2 column) {
	return all(greaterThanEqual(column, ivec2(0))) && all(lessThan(column, ivec2(WM_SIZE)));
}

// 1 where rain and snow reach the air at this point, 0 under a block, -1 outside the map.
// Blended over the four nearest columns, so wet ground fades out over a block under a roof edge.
float weatherReach(vec3 feet) {
	vec3 g = feet + cameraPositionFract + vec3(WM_CENTER);
	vec2 base = g.xz - 0.5;
	ivec2 c0 = ivec2(floor(base));
	vec2 f = base - vec2(c0);
	if (!weatherInMap(c0) || !weatherInMap(c0 + 1)) return -1.0;
	int y = int(floor(g.y));
	float e00 = weatherColumnOpen(c0, y);
	float e10 = weatherColumnOpen(c0 + ivec2(1, 0), y);
	float e01 = weatherColumnOpen(c0 + ivec2(0, 1), y);
	float e11 = weatherColumnOpen(c0 + ivec2(1, 1), y);
	return mix(mix(e00, e10, f.x), mix(e01, e11, f.x), f.y);
}

// The same for a single falling particle, without blending: 1 open, 0 under a block or unknown.
float weatherReachPoint(vec3 feet) {
	ivec3 c = weatherCell(feet);
	if (!weatherInMap(c.xz)) return 0.0;
	return weatherColumnOpen(c.xz, c.y);
}

// How much of a basin the column at this point is: 1 when every neighbour is higher, so water
// has nowhere to run, down to 0 on flat or sloping ground, where it drains away.
float weatherBasin(vec3 feet) {
	ivec3 c = weatherCell(feet);
	if (!weatherInMap(c.xz - 1) || !weatherInMap(c.xz + 1)) return 0.0;
	int own;
	if (!weatherColumnTop(c.xz, own)) return 0.0;
	float higher = 0.0;
	const ivec2 sides[4] = ivec2[4](ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1));
	for (int i = 0; i < 4; i++) {
		int top;
		if (!weatherColumnTop(c.xz + sides[i], top)) return 0.0;
		if (top < own) return 0.0;
		if (top > own) higher += 1.0;
	}
	return higher / 4.0;
}
#endif

// Whether weather reaches a surface, from the map where it covers the point and from the sky
// light of the game everywhere else. worldNormal points out of the surface.
float weatherExposure(vec3 feet, vec3 worldNormal, float lmSky) {
	float fromSkyLight = smoothstep(0.6, 0.92, lmSky);
#if defined USE_WEATHER_MAP && !defined SHADOW_PASS
	float reach = weatherReach(feet + worldNormal * 0.5);
	if (reach >= 0.0) return reach * smoothstep(0.2, 0.5, lmSky);
#endif
	return fromSkyLight;
}

#endif
