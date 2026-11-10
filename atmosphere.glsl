// VanillaDeluxe - physically based single scattering atmosphere with a
// multi-scatter approximation. Rayleigh, Mie and ozone follow the coefficients
// published by Hillaire (2020). Evaluated once per frame into a small sky LUT.
#ifndef VD_ATMOSPHERE_INCLUDED
#define VD_ATMOSPHERE_INCLUDED 1

const float ATM_GROUND = 6360000.0;
const float ATM_TOP = 6460000.0;
const float ATM_HEIGHT_R = 8000.0;
const float ATM_HEIGHT_M = 1200.0;
const float ATM_SUN_RADIANCE = 12.5;
const float ATM_MOON_RADIANCE = 0.075;

vec3 atmBetaRayleigh() {
	// A stronger Rayleigh term pushes sunsets from orange into deep crimson.
	float crimson = float(SUNSET_CRIMSON) / 100.0;
	return vec3(5.802e-6, 13.558e-6, 33.1e-6) * (1.0 + 0.55 * crimson);
}
const float ATM_BETA_M = 3.996e-6;
const vec3 ATM_BETA_O = vec3(0.650e-6, 1.881e-6, 0.085e-6);

// Dust and aerosols absorb short wavelengths more strongly, like real particles do. A long
// path through them near the horizon leaves mainly deep red light.
vec3 atmExtinctionMie() {
	float crimson = float(SUNSET_CRIMSON) / 100.0;
	return 8.4e-6 * mix(vec3(1.0), vec3(0.78, 1.30, 2.05), crimson);
}

vec3 atmDensities(float h) {
	float ozone = max(0.0, 1.0 - abs(h - 25000.0) / 15000.0);
	return vec3(exp(-h / ATM_HEIGHT_R), exp(-h / ATM_HEIGHT_M), ozone);
}
float atmRayleighPhase(float c) {
	return 0.0596831 * (1.0 + c * c);
}
float atmMiePhase(float c, float g) {
	float g2 = g * g;
	return 0.0795775 * (1.0 - g2) / pow(max(1.0 + g2 - 2.0 * g * c, 1e-4), 1.5);
}
// Distance to the far side of a sphere around the planet centre. Negative when missed.
float atmSphereFar(vec3 ro, vec3 rd, float radius) {
	float b = dot(ro, rd);
	float disc = b * b - dot(ro, ro) + radius * radius;
	if (disc < 0.0) return -1.0;
	return -b + sqrt(disc);
}
float atmSphereNear(vec3 ro, vec3 rd, float radius) {
	float b = dot(ro, rd);
	float disc = b * b - dot(ro, ro) + radius * radius;
	if (disc < 0.0) return -1.0;
	return -b - sqrt(disc);
}

// Transmittance from a point towards the light. Goes to zero behind the planet.
vec3 atmTransmittance(vec3 p, vec3 lightDir) {
	float groundHit = atmSphereNear(p, lightDir, ATM_GROUND);
	if (groundHit > 0.0) return vec3(0.0);
	float tMax = atmSphereFar(p, lightDir, ATM_TOP);
	if (tMax <= 0.0) return vec3(1.0);
	float dt = tMax / 5.0;
	vec3 opticalDepth = vec3(0.0);
	for (int i = 0; i < 5; i++) {
		vec3 q = p + lightDir * (float(i) + 0.5) * dt;
		opticalDepth += atmDensities(length(q) - ATM_GROUND) * dt;
	}
	return exp(-(atmBetaRayleigh() * opticalDepth.x + atmExtinctionMie() * opticalDepth.y + ATM_BETA_O * opticalDepth.z));
}

vec3 atmOrigin() {
	return vec3(0.0, ATM_GROUND + 300.0 + max(eyeAltitude, 0.0) * 2.0, 0.0);
}

vec3 atmSkyRadiance(vec3 rd, vec3 sunDir, vec3 moonDir, int steps) {
	vec3 ro = atmOrigin();
	float tTop = atmSphereFar(ro, rd, ATM_TOP);
	if (tTop <= 0.0) return vec3(0.0);
	float tGround = atmSphereNear(ro, rd, ATM_GROUND);
	bool hitsGround = tGround > 0.0;
	float tMax = hitsGround ? tGround : tTop;

	float cosSun = dot(rd, sunDir);
	float cosMoon = dot(rd, moonDir);
	float phaseSunR = atmRayleighPhase(cosSun);
	float phaseSunM = atmMiePhase(cosSun, 0.78);
	float phaseMoonR = atmRayleighPhase(cosMoon);
	float phaseMoonM = atmMiePhase(cosMoon, 0.78);
	vec3 betaR = atmBetaRayleigh();
	vec3 extinctionM = atmExtinctionMie();

	// Light that has scattered more than once fills in the blue of the sky.
	// It inherits the colour of the sunlight, which turns the low sky red at sunset.
	float sunLevel = saturate(sunDir.y * 2.4 + 0.22);
	float moonLevel = saturate(moonDir.y * 2.4 + 0.22);
	vec3 multiScatterTint = vec3(0.46, 0.70, 1.0);
	vec3 sunLightColor = sqrt(atmTransmittance(ro, normalize(sunDir + vec3(0.0, 0.04, 0.0))));
	vec3 multiLight = ATM_SUN_RADIANCE * sunLevel * sunLightColor + vec3(ATM_MOON_RADIANCE * moonLevel);

	vec3 radiance = vec3(0.0);
	vec3 viewOpticalDepth = vec3(0.0);
	float previousT = 0.0;
	float stepsF = float(steps);
	for (int i = 0; i < steps; i++) {
		float s = (float(i) + 0.5) / stepsF;
		float t = tMax * s * s;
		float dt = t - previousT;
		previousT = t;
		vec3 p = ro + rd * t;
		vec3 densities = atmDensities(length(p) - ATM_GROUND);
		viewOpticalDepth += densities * dt;
		vec3 viewT = exp(-(betaR * viewOpticalDepth.x + extinctionM * viewOpticalDepth.y + ATM_BETA_O * viewOpticalDepth.z));

		vec3 scatterR = betaR * densities.x;
		vec3 scatterM = vec3(ATM_BETA_M) * densities.y;

		vec3 sunT = atmTransmittance(p, sunDir);
		vec3 moonT = atmTransmittance(p, moonDir);
		vec3 single = ATM_SUN_RADIANCE * sunT * (scatterR * phaseSunR + scatterM * phaseSunM)
			+ ATM_MOON_RADIANCE * moonT * (scatterR * phaseMoonR + scatterM * phaseMoonM);
		vec3 multi = (scatterR + scatterM) * multiScatterTint * multiLight * 0.085;
		radiance += viewT * (single + multi) * dt;
	}
	if (hitsGround) {
		// Distant land seen through the haze. Soft and neutral, so it meets the horizon cleanly.
		vec3 viewT = exp(-(betaR * viewOpticalDepth.x + extinctionM * viewOpticalDepth.y + ATM_BETA_O * viewOpticalDepth.z));
		vec3 groundLight = ATM_SUN_RADIANCE * atmTransmittance(ro, sunDir) * saturate(sunDir.y)
			+ ATM_MOON_RADIANCE * saturate(moonDir.y) + multiLight * 0.12;
		radiance += viewT * groundLight * vec3(0.085, 0.10, 0.11) * INV_PI;
	}
	// Night sky glow so that moonless nights never fall to pure black.
	float zenith = saturate(rd.y);
	radiance += vec3(0.0016, 0.0022, 0.0042) * (1.0 - 0.5 * zenith);
	return radiance;
}

// Rain flattens the sky to a brightness matched grey.
vec3 atmApplyWeather(vec3 radiance) {
	float lum = luminance(radiance);
	vec3 overcast = lum * vec3(0.92, 0.97, 1.05) * 0.55;
	return mix(radiance, overcast, rainStrength * 0.92);
}

vec3 atmSunIlluminance(vec3 sunDir) {
	return 8.6 * atmTransmittance(atmOrigin(), sunDir);
}
vec3 atmMoonIlluminance() {
	// Full moon is brightest, the new moon leaves only a faint ambient light.
	float phase = abs(float(moonPhase) - 4.0) / 4.0;
	return vec3(0.55, 0.68, 1.0) * mix(0.07, 0.22, phase);
}

#endif
