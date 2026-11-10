// VanillaDeluxe - display transforms and colour grading.
// ACES curve fit: Stephen Hill. AgX polynomial fit: Benjamin Wrensch.
#ifndef VD_TONEMAP_INCLUDED
#define VD_TONEMAP_INCLUDED 1

vec3 acesFit(vec3 v) {
	const mat3 inputMat = mat3(
		0.59719, 0.07600, 0.02840,
		0.35458, 0.90834, 0.13383,
		0.04823, 0.01566, 0.83777);
	const mat3 outputMat = mat3(
		1.60475, -0.10208, -0.00327,
		-0.53108, 1.10813, -0.07276,
		-0.07367, -0.00605, 1.07602);
	v = inputMat * v;
	vec3 a = v * (v + 0.0245786) - 0.000090537;
	vec3 b = v * (0.983729 * v + 0.4329510) + 0.238081;
	return saturate(outputMat * (a / b));
}

vec3 agxContrast(vec3 x) {
	vec3 x2 = x * x;
	vec3 x4 = x2 * x2;
	return 15.5 * x4 * x2 - 40.14 * x4 * x + 31.96 * x4 - 6.868 * x2 * x + 0.4298 * x2 + 0.1191 * x - 0.00232;
}
vec3 agxTonemap(vec3 v, float power, float saturation) {
	const mat3 agxIn = mat3(
		0.842479062253094, 0.0423282422610123, 0.0423756549057051,
		0.0784335999999992, 0.878468636469772, 0.0784336,
		0.0792237451477643, 0.0791661274605434, 0.879142973793104);
	const mat3 agxOut = mat3(
		1.19687900512017, -0.0528968517574562, -0.0529716355144438,
		-0.0980208811401368, 1.15190312990417, -0.0980434501171241,
		-0.0990297440797205, -0.0989611768448433, 1.15107367264116);
	const float minEv = -12.47393;
	const float maxEv = 4.026069;
	v = agxIn * max(v, vec3(1e-6));
	v = clamp(log2(v), vec3(minEv), vec3(maxEv));
	v = (v - minEv) / (maxEv - minEv);
	v = agxContrast(v);
	float luma = dot(v, vec3(0.2126, 0.7152, 0.0722));
	v = pow(max(v, vec3(0.0)), vec3(power));
	v = luma + saturation * (v - luma);
	return saturate(agxOut * v);
}

// Output of both curves is linear light that still needs the display encode.
vec3 applyTonemap(vec3 c) {
#if TONEMAP == 0
	return acesFit(c * 0.75);
#elif TONEMAP == 1
	return agxTonemap(c, 1.40, 1.38);
#else
	return agxTonemap(c, 1.0, 1.05);
#endif
}

vec3 applyLook(vec3 c) {
	float l = luminance(c);
#if LOOK_PROFILE == 1
	// Crimson Real: deep warm reds in the shadows, slightly muted greens.
	c.g = mix(c.g, c.g * 0.965 + c.r * 0.02, 0.8);
	// Oranges lean towards red. Only tones where red clearly leads are moved.
	float warmth = saturate((c.r - max(c.g, c.b)) * 3.2);
	c.g *= 1.0 - 0.08 * warmth;
	c.b *= 1.0 - 0.04 * warmth;
	vec3 shadowTint = vec3(1.055, 0.965, 0.945);
	vec3 highlightTint = vec3(1.018, 1.000, 0.972);
	c *= mix(shadowTint, highlightTint, smoothstep(0.0, 0.55, l));
	c += vec3(0.0065, 0.0005, 0.0) * (1.0 - smoothstep(0.0, 0.18, l));
#elif LOOK_PROFILE == 2
	// Natural Warm: a gentle shift towards golden light.
	c *= mix(vec3(1.012, 1.0, 0.985), vec3(1.022, 1.002, 0.962), smoothstep(0.0, 0.7, l));
#endif
	return c;
}

vec3 applyGrade(vec3 c) {
	float contrast = float(CONTRAST) / 100.0;
	float saturation = float(SATURATION) / 100.0;
	c = applyLook(c);
	float l = luminance(c);
	c = mix(vec3(l), c, saturation);
	c = mix(vec3(0.18), c, contrast);
	return saturate(c);
}

vec3 linearToSrgb(vec3 c) {
	vec3 low = c * 12.92;
	vec3 high = 1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055;
	return mix(high, low, vec3(lessThan(c, vec3(0.0031308))));
}

#endif
