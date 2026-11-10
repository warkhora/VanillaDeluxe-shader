// VanillaDeluxe - BRDF and labPBR material decoding.
#ifndef VD_BRDF_INCLUDED
#define VD_BRDF_INCLUDED 1

// Index of refraction based F0 for the labPBR hardcoded metals (230 to 237).
const vec3 LABPBR_METALS[8] = vec3[8](
	vec3(0.561, 0.570, 0.580), // iron
	vec3(1.000, 0.766, 0.336), // gold
	vec3(0.913, 0.921, 0.925), // aluminium
	vec3(0.550, 0.556, 0.554), // chrome
	vec3(0.955, 0.638, 0.538), // copper
	vec3(0.632, 0.626, 0.641), // lead
	vec3(0.673, 0.637, 0.585), // platinum
	vec3(0.972, 0.960, 0.915)  // silver
);

// f0Raw is the labPBR green channel: below 230 linear dielectric F0, 230 to 237
// a hardcoded metal, anything above uses the albedo as metal colour.
void decodeReflectance(float f0Raw, vec3 albedo, out vec3 f0, out float metalness) {
	int value = int(f0Raw * 255.0 + 0.5);
	if (value < 230) {
		f0 = vec3(f0Raw);
		metalness = 0.0;
	} else if (value <= 237) {
		f0 = LABPBR_METALS[value - 230];
		metalness = 1.0;
	} else {
		f0 = albedo;
		metalness = 1.0;
	}
}
// labPBR blue channel: 0 to 64 porosity, 65 to 255 subsurface scattering.
float decodeSubsurface(float raw) {
	int value = int(raw * 255.0 + 0.5);
	return value < 65 ? 0.0 : float(value - 65) / 190.0;
}
float decodePorosity(float raw) {
	int value = int(raw * 255.0 + 0.5);
	return value < 65 ? float(value) / 64.0 : 0.0;
}

float distributionGGX(float NoH, float a) {
	float a2 = a * a;
	float d = (NoH * a2 - NoH) * NoH + 1.0;
	return a2 / (PI * d * d + 1e-7);
}
float visibilitySmith(float NoV, float NoL, float a) {
	return 0.5 / max(mix(2.0 * NoL * NoV, NoL + NoV, a), 1e-4);
}
vec3 fresnelSchlick(float cosTheta, vec3 f0) {
	return f0 + (vec3(1.0) - f0) * pow5(1.0 - saturate(cosTheta));
}
float fresnelDielectric(float cosTheta, float f0) {
	return f0 + (1.0 - f0) * pow5(1.0 - saturate(cosTheta));
}
vec3 specularGGX(vec3 N, vec3 V, vec3 L, float roughness, vec3 f0) {
	vec3 H = normalize(V + L);
	float NoL = saturate(dot(N, L));
	float NoV = max(dot(N, V), 1e-3);
	float NoH = saturate(dot(N, H));
	float VoH = saturate(dot(V, H));
	// Roughness floor widens the disc of the sun so that highlights stay stable.
	float a = max(roughness * roughness, 0.0016);
	return distributionGGX(NoH, a) * visibilitySmith(NoV, NoL, a) * fresnelSchlick(VoH, f0) * NoL;
}
// Burley diffuse, flattens at grazing angles on rough surfaces.
float diffuseBurley(float NoL, float NoV, float VoH, float roughness) {
	float fd90 = 0.5 + 2.0 * roughness * VoH * VoH;
	float lightScatter = 1.0 + (fd90 - 1.0) * pow5(1.0 - NoL);
	float viewScatter = 1.0 + (fd90 - 1.0) * pow5(1.0 - NoV);
	return lightScatter * viewScatter * INV_PI;
}
// Henyey-Greenstein phase function.
float phaseHG(float c, float g) {
	float g2 = g * g;
	return 0.0795775 * (1.0 - g2) / pow(max(1.0 + g2 - 2.0 * g * c, 1e-4), 1.5);
}

#endif
