// VanillaDeluxe - block ids from block.properties and the built-in material table
// that gives vanilla textures plausible PBR values.
#ifndef VD_MATERIAL_INCLUDED
#define VD_MATERIAL_INCLUDED 1

const int ID_PLANT = 10001;
const int ID_PLANT_LOWER = 10002;
const int ID_PLANT_UPPER = 10003;
const int ID_LEAVES = 10004;
const int ID_VINES = 10005;
const int ID_LAVA = 10010;
const int ID_FIRE = 10011;
const int ID_EMISSIVE_FULL = 10012;
const int ID_EMISSIVE_PARTIAL = 10013;
// The same two kinds of light source, split by the colour of their light.
const int ID_SOUL_FIRE = 10014;
const int ID_EMISSIVE_COOL = 10015;
const int ID_SOUL_PARTIAL = 10016;
const int ID_RED_PARTIAL = 10017;
const int ID_PURPLE_PARTIAL = 10018;
// Torches give off smoke, so they are kept apart from lanterns and candles.
const int ID_TORCH = 10019;
const int ID_SOUL_TORCH = 10008;
const int ID_METAL_IRON = 10020;
const int ID_METAL_GOLD = 10021;
const int ID_METAL_COPPER = 10022;
const int ID_POLISHED = 10023;
const int ID_GEM = 10024;
const int ID_ICE_SOLID = 10025;
const int ID_SNOW = 10026;
const int ID_WOOD = 10027;
const int ID_WATER = 10030;
const int ID_GLASS = 10031;
const int ID_STAINED_GLASS = 10032;
const int ID_SLIME = 10033;
const int ID_PORTAL = 10034;
const int ID_ICE = 10035;
const int ID_END_PORTAL = 10040;

bool isFoliageId(int id) {
	return id >= ID_PLANT && id <= ID_VINES;
}

float subsurfaceToRaw(float amount) {
	return (65.0 + 190.0 * saturate(amount)) / 255.0;
}

// Defaults for blocks without a PBR resource pack. All outputs use the labPBR encoding.
void integratedMaterial(int id, float lum, float blockLight, out float smoothness, out float f0Raw, out float emission, out float subsurfaceRaw) {
	smoothness = 0.10 + lum * 0.14;
	f0Raw = 0.04;
	emission = 0.0;
	subsurfaceRaw = 0.0;

	if (id == ID_PLANT || id == ID_PLANT_LOWER || id == ID_PLANT_UPPER) {
		smoothness = 0.32;
		subsurfaceRaw = subsurfaceToRaw(0.75);
	} else if (id == ID_LEAVES || id == ID_VINES) {
		smoothness = 0.42;
		subsurfaceRaw = subsurfaceToRaw(0.60);
	} else if (id == ID_METAL_IRON) {
		smoothness = 0.58 + lum * 0.30;
		f0Raw = 230.0 / 255.0;
	} else if (id == ID_METAL_GOLD) {
		smoothness = 0.60 + lum * 0.30;
		f0Raw = 231.0 / 255.0;
	} else if (id == ID_METAL_COPPER) {
		smoothness = 0.50 + lum * 0.30;
		f0Raw = 234.0 / 255.0;
	} else if (id == ID_POLISHED) {
		smoothness = 0.44 + lum * 0.18;
		f0Raw = 0.05;
	} else if (id == ID_GEM) {
		smoothness = 0.80;
		f0Raw = 0.13;
	} else if (id == ID_LAVA) {
		// Molten areas are glossy, the cooling crust is rough. Lava always glows.
		float molten = smoothstep(0.35, 0.85, lum);
		smoothness = mix(0.28, 0.62, molten);
		f0Raw = 0.05;
		emission = 0.35 + 0.65 * smoothstep(0.25, 0.85, lum);
	} else if (id == ID_ICE_SOLID) {
#ifdef ICE_REFLECTIVITY
		smoothness = 0.90;
		f0Raw = 0.025;
#else
		smoothness = 0.40;
		f0Raw = 0.02;
#endif
		subsurfaceRaw = subsurfaceToRaw(0.25);
	} else if (id == ID_SNOW) {
		smoothness = 0.34;
		f0Raw = 0.02;
		subsurfaceRaw = subsurfaceToRaw(0.35);
	} else if (id == ID_WOOD) {
		smoothness = 0.22 + lum * 0.14;
	}

#ifdef INTEGRATED_EMISSION
	bool partialLight = id == ID_EMISSIVE_PARTIAL || id == ID_SOUL_PARTIAL || id == ID_RED_PARTIAL || id == ID_PURPLE_PARTIAL
		|| id == ID_TORCH || id == ID_SOUL_TORCH;
	if (id == ID_FIRE || id == ID_SOUL_FIRE) {
		emission = 0.9;
	} else if (id == ID_EMISSIVE_FULL || id == ID_EMISSIVE_COOL) {
		emission = 0.25 + 0.75 * smoothstep(0.25, 0.85, lum);
	} else if (id != ID_LAVA && (partialLight || blockLight > 0.01)) {
		// Any block that emits light glows only in its brightest pixels.
		emission = smoothstep(0.55, 0.92, lum) * max(blockLight, partialLight ? 0.8 : 0.0);
	}
#endif
}

#endif
