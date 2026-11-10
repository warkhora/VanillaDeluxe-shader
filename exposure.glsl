// VanillaDeluxe - automatic exposure, stored in a single pixel. The bloom buffer is
// already a wide blur of the scene, so a few reads give a stable average brightness.
#include "/lib/settings.glsl"
#include "/lib/common.glsl"

#ifdef VSH
void main() {
	gl_Position = ftransform();
}
#endif

#ifdef FSH
uniform sampler2D colortex8;
uniform sampler2D colortex13;
#ifdef LENS_FLARE
uniform sampler2D colortex7;
#include "/lib/sky.glsl"
#endif
#ifdef DEPTH_OF_FIELD
uniform sampler2D depthtex0;
uniform sampler2D colortex3;
#endif

/* RENDERTARGETS: 13 */
layout(location = 0) out vec4 outExposure;

void main() {
	float compensation = pow(2.0, float(EXPOSURE_COMPENSATION) / 10.0);
#ifdef AUTO_EXPOSURE
	float logSum = 0.0;
	float total = 0.0;
	for (int y = 0; y < 5; y++) {
		for (int x = 0; x < 5; x++) {
			vec2 uv = (vec2(x, y) + 0.5) / 5.0;
			vec2 fromCenter = (uv - 0.5) * 2.0;
			float weight = 1.0 - 0.7 * dot(fromCenter, fromCenter) * 0.5;
			float l = luminance(texture(colortex8, uv).rgb);
			logSum += log2(max(l, 1e-4)) * weight;
			total += weight;
		}
	}
	float average = pow(2.0, logSum / total);
	float target = 0.20 / max(average, 1e-4);
	// Compressing the range keeps night dark and midday from being pushed to grey.
	target = pow(target, 0.56) * 0.58;
	target = clamp(target, 0.20, 2.1);

	float previous = texelFetch(colortex13, ivec2(0), 0).r;
	if (!(previous > 0.001 && previous < 64.0)) previous = target;
	float rate = target > previous ? 0.75 : 1.5;
	float exposure = mix(previous, target, 1.0 - exp(-frameTime * rate));
	outExposure = vec4(exposure, 0.0, 0.0, 1.0);
#else
	outExposure = vec4(0.8, 0.0, 0.0, 1.0);
#endif
	outExposure.g = compensation;
#ifdef LENS_FLARE
	// How much of the sun or moon is seen, for the lens flare. Once per frame here, instead of in
	// every pixel of the final pass.
	outExposure.a = 0.0;
	vec4 lightClip = gbufferProjection * vec4(shadowLightPosition, 1.0);
	if (lightClip.w > 0.0) {
		vec2 lightUv = lightClip.xy / lightClip.w * 0.5 + 0.5;
		if (all(greaterThan(lightUv, vec2(-0.1))) && all(lessThan(lightUv, vec2(1.1)))) {
			float expected = max(luminance(readLightColor()), 1e-5) * 3.5;
			float visible = 0.0;
			for (int i = 0; i < 5; i++) {
				vec2 o = i == 0 ? vec2(0.0) : vec2(cos(float(i) * 1.571), sin(float(i) * 1.571)) * 0.004;
				visible += saturate(luminance(texture(colortex7, lightUv + o).rgb) / expected);
			}
			float edge = max(abs(lightUv.x - 0.5), abs(lightUv.y - 0.5));
			outExposure.a = visible / 5.0 * (1.0 - rainStrength) * (1.0 - smoothstep(0.45, 0.6, edge));
		}
	}
#else
	outExposure.a = 1.0;
#endif
#ifdef DEPTH_OF_FIELD
	// Autofocus on what is in the middle of the screen, averaged over a small cross so that a single
	// blade of grass does not pull the focus, and eased over time like a camera that refocuses.
	float focusSum = 0.0;
	float focusCount = 0.0;
	for (int i = 0; i < 5; i++) {
		vec2 o = i == 0 ? vec2(0.0) : vec2(cos(float(i) * 1.571), sin(float(i) * 1.571)) * vec2(0.012 / aspectRatio, 0.012);
		ivec2 p = ivec2((vec2(0.5) + o) * vec2(viewWidth, viewHeight));
		float d = texelFetch(depthtex0, p, 0).r;
		if (d < 1.0 && unpackMaterialClass(texelFetch(colortex3, p, 0).b) == MAT_HAND) continue;
		float z = d >= 1.0 ? 256.0 : min(linearDepth(d), 256.0);
		focusSum += log2(max(z, 0.1));
		focusCount += 1.0;
	}
	float previousFocus = texelFetch(colortex13, ivec2(0), 0).b;
	float targetFocus = focusCount > 0.0 ? exp2(focusSum / focusCount) : previousFocus;
	if (!(previousFocus > 0.05 && previousFocus < 1000.0)) previousFocus = max(targetFocus, 0.1);
	outExposure.b = exp2(mix(log2(previousFocus), log2(max(targetFocus, 0.1)), 1.0 - exp(-frameTime * 3.0)));
#endif
}
#endif
