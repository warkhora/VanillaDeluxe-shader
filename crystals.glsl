// VanillaDeluxe - End crystals. gbuffers_entities records where each crystal is: every vertex adds
// its position to a slot picked by the 8 x 8 x 8 block region it lies in, so the slot ends up with
// the centre of the crystal. The volumetric pass reads the centres and sends light rays out from
// them. Row 0 of the image counts the vertices, rows 1 to 3 hold the sums of x, y and z.
#ifndef VD_CRYSTALS_INCLUDED
#define VD_CRYSTALS_INCLUDED 1

const int ID_END_CRYSTAL = 20000;
const int CRYSTAL_SLOTS = 32;
const float CRYSTAL_SCALE = 4.0;
const float CRYSTAL_OFFSET = 4096.0;

int crystalSlot(vec3 worldPos) {
	ivec3 region = ivec3(floor(worldPos / 8.0));
	return int(uint(region.x * 73856093 ^ region.y * 19349663 ^ region.z * 83492791) % uint(CRYSTAL_SLOTS));
}

#ifdef CRYSTAL_WRITER
layout(r32ui) uniform uimage2D rtCrystalImg;
void recordCrystal(vec3 feet) {
	int slot = crystalSlot(feet + cameraPosition);
	uvec3 packed_ = uvec3(clamp(feet * CRYSTAL_SCALE + CRYSTAL_OFFSET, vec3(0.0), vec3(8191.0)));
	imageAtomicAdd(rtCrystalImg, ivec2(slot, 0), 1u);
	imageAtomicAdd(rtCrystalImg, ivec2(slot, 1), packed_.x);
	imageAtomicAdd(rtCrystalImg, ivec2(slot, 2), packed_.y);
	imageAtomicAdd(rtCrystalImg, ivec2(slot, 3), packed_.z);
}
#else
uniform usampler2D rtCrystalSampler;
// Centre of the crystal in a slot, in feet space. False when the slot is empty.
bool crystalCenter(int slot, out vec3 feet) {
	uint count = texelFetch(rtCrystalSampler, ivec2(slot, 0), 0).r;
	feet = vec3(0.0);
	if (count == 0u) return false;
	vec3 sum = vec3(texelFetch(rtCrystalSampler, ivec2(slot, 1), 0).r, texelFetch(rtCrystalSampler, ivec2(slot, 2), 0).r, texelFetch(rtCrystalSampler, ivec2(slot, 3), 0).r);
	feet = (sum / float(count) - CRYSTAL_OFFSET) / CRYSTAL_SCALE;
	return true;
}

// Light that the crystals send towards the eye along a view ray: a glow around each one, and slow
// turning rays that reach far out into the dark. maxDist is the distance to the surface behind.
vec3 crystalRays(vec3 dir, float maxDist) {
	vec3 light = vec3(0.0);
	vec3 seen[8];
	int found = 0;
	float t = frameTimeCounter;
	for (int i = 0; i < CRYSTAL_SLOTS; i++) {
		vec3 c;
		if (!crystalCenter(i, c)) continue;
		// A crystal on the edge of a region fills two slots. Count it once.
		bool repeated = false;
		for (int j = 0; j < 8; j++) {
			if (j >= found) break;
			if (distance(seen[j], c) < 3.0) repeated = true;
		}
		if (repeated || found >= 8) continue;
		seen[found] = c;
		found++;
		float along = dot(c, dir);
		if (along <= 0.0 || along > maxDist + 1.5) continue;
		vec3 perpendicular = c - dir * along;
		float off = length(perpendicular);
		vec3 side = mat3(gbufferModelView) * perpendicular;
		float angle = atan(side.y, side.x);
		float seed = float(i) * 1.7;
		float rays = pow(0.5 + 0.5 * sin(angle * 7.0 + t * 0.35 + seed), 8.0) + 0.6 * pow(0.5 + 0.5 * sin(angle * 13.0 - t * 0.55 + seed * 2.3), 12.0);
		float glow = exp(-off * 1.6) * 0.9;
		float shafts = rays * exp(-off * 0.22) * smoothstep(0.4, 1.6, off) * 0.35;
		light += vec3(1.0, 0.42, 0.95) * (glow + shafts) / (1.0 + along * 0.015);
	}
	return light;
}
#endif

#endif
