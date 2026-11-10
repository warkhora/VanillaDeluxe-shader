// VanillaDeluxe - two pass spatial bilateral filter for the indirect light: first along x,
// then along y. Blur stops at depth and normal edges, and at changes in brightness that are
// larger than the noise measured at that pixel. Noisy light is smoothed widely, while the edge
// of a shadow, which has no noise on either side, stays sharp. Newly revealed pixels have no
// history yet and get the widest filter.
#include "/lib/settings.glsl"
#include "/lib/common.glsl"

#ifdef VSH
void main() {
	gl_Position = ftransform();
}
#endif

#ifdef FSH
uniform sampler2D colortex14;

#ifdef DENOISE_HORIZONTAL
uniform sampler2D colortex10;
#define DENOISE_INPUT colortex10
const ivec2 DENOISE_AXIS = ivec2(1, 0);
#else
uniform sampler2D colortex19;
#define DENOISE_INPUT colortex19
const ivec2 DENOISE_AXIS = ivec2(0, 1);
#endif

/* RENDERTARGETS: 19 */
layout(location = 0) out vec4 outFiltered;

void main() {
	ivec2 px = ivec2(gl_FragCoord.xy);
	ivec2 maxPx = ivec2(viewWidth, viewHeight) / 2 - 1;
	vec4 center = texelFetch(DENOISE_INPUT, px, 0);
	vec4 centerHistory = texelFetch(colortex14, px, 0);
	float centerZ = centerHistory.r;
	if (centerZ >= 1e4) {
		outFiltered = center;
		return;
	}

	vec3 centerNormal = unpackNormalFloat(centerHistory.a);
	float frames = centerHistory.g;
	float centerLum = luminance(center.rgb);
	// The temporal pass keeps the second moment of the brightness of single frames. Their
	// variance, divided by the number of distinct samples behind the average, is the noise
	// that is left. The noise repeats every 16 frames, so more history adds no new samples.
	float variance = max(centerHistory.b - centerLum * centerLum, 0.0);
	float noise = sqrt(variance / (min(frames, 16.0) + 1.0));
	float tolerance = 0.03 + centerLum * 0.1 + noise * 3.0 + 0.5 / (frames + 1.0);
	int spacing = DENOISER_RADIUS + (frames < 6.0 ? 1 : 0);

	vec3 lightSum = vec3(0.0);
	float occlusionSum = 0.0;
	float lightTotal = 0.0;
	float occlusionTotal = 0.0;
	for (int i = -4; i <= 4; i++) {
		ivec2 p = clamp(px + DENOISE_AXIS * i * spacing, ivec2(0), maxPx);
		vec4 history = texelFetch(colortex14, p, 0);
		float kernel = exp(-float(i * i) / 9.0);
		float depthWeight = exp(-abs(history.r - centerZ) / (0.02 * centerZ + 0.05));
		if (depthWeight < 0.01) continue;
		float normalWeight = pow(saturate(dot(unpackNormalFloat(history.a), centerNormal)), 16.0);
		float edge = kernel * depthWeight * normalWeight;
		if (edge < 1e-4) continue;

		vec4 s = texelFetch(DENOISE_INPUT, p, 0);
		float lightWeight = edge * exp(-abs(luminance(s.rgb) - centerLum) / tolerance);
		lightSum += s.rgb * lightWeight;
		lightTotal += lightWeight;
		occlusionSum += s.a * edge;
		occlusionTotal += edge;
	}

	outFiltered = vec4(
		lightTotal > 1e-5 ? lightSum / lightTotal : center.rgb,
		occlusionTotal > 1e-5 ? occlusionSum / occlusionTotal : center.a);
}
#endif
