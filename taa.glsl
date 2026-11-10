// VanillaDeluxe - temporal anti-aliasing. Resolves all per-frame noise left by shadows,
// reflections and the indirect trace. Output is stored in colortex7, which is also the
// history of the next frame and the input of the indirect trace.
#include "/lib/settings.glsl"
#include "/lib/common.glsl"

#ifdef VSH
out vec2 texCoord;
void main() {
	gl_Position = ftransform();
	texCoord = gl_MultiTexCoord0.xy;
}
#endif

#ifdef FSH
in vec2 texCoord;

uniform sampler2D depthtex0;
uniform sampler2D colortex0;
uniform sampler2D colortex3;
uniform sampler2D colortex7;

/* RENDERTARGETS: 7 */
layout(location = 0) out vec4 outHistory;

#ifdef TEMPORAL_AA

vec3 toYCoCg(vec3 c) {
	return vec3(0.25 * c.r + 0.5 * c.g + 0.25 * c.b,
		0.5 * c.r - 0.5 * c.b,
		-0.25 * c.r + 0.5 * c.g - 0.25 * c.b);
}
vec3 fromYCoCg(vec3 c) {
	return vec3(c.x + c.y - c.z, c.x + c.z, c.x - c.y - c.z);
}
// Filmic compression keeps very bright pixels from dominating the neighbourhood.
vec3 compress(vec3 c) {
	return c / (1.0 + luminance(c));
}
vec3 expand(vec3 c) {
	return c / max(1.0 - luminance(c), 1e-3);
}

vec3 compressedHistory(vec2 uv) {
	return compress(textureLod(colortex7, uv, 0.0).rgb);
}
// Catmull-Rom history lookup in five bilinear taps, which keeps the image sharp in motion. The
// filter has negative lobes. Working on compressed values keeps very bright neighbours from
// pulling the result below zero, which would show up as black edges while the camera moves.
// Returns compressed colour.
vec3 historyCatmullRom(vec2 uv, vec2 size) {
	vec2 position = uv * size;
	vec2 center = floor(position - 0.5) + 0.5;
	vec2 f = position - center;
	vec2 f2 = f * f;
	vec2 f3 = f * f2;
	vec2 w0 = -0.5 * f3 + f2 - 0.5 * f;
	vec2 w1 = 1.5 * f3 - 2.5 * f2 + 1.0;
	vec2 w2 = -1.5 * f3 + 2.0 * f2 + 0.5 * f;
	vec2 w3 = 0.5 * f3 - 0.5 * f2;
	vec2 w12 = w1 + w2;
	vec2 tc0 = (center - 1.0) / size;
	vec2 tc12 = (center + w2 / w12) / size;
	vec2 tc3 = (center + 2.0) / size;
	vec3 sum = compressedHistory(vec2(tc12.x, tc0.y)) * (w12.x * w0.y)
		+ compressedHistory(vec2(tc0.x, tc12.y)) * (w0.x * w12.y)
		+ compressedHistory(tc12) * (w12.x * w12.y)
		+ compressedHistory(vec2(tc3.x, tc12.y)) * (w3.x * w12.y)
		+ compressedHistory(vec2(tc12.x, tc3.y)) * (w12.x * w3.y);
	float total = (w12.x * w0.y) + (w0.x * w12.y) + (w12.x * w12.y) + (w3.x * w12.y) + (w12.x * w3.y);
	return max(sum / total, vec3(0.0));
}

// Pulls the history point towards the box centre until it lies inside the box.
vec3 clipToBox(vec3 history, vec3 center, vec3 extent) {
	vec3 offset = history - center;
	vec3 unit = abs(offset) / max(extent, vec3(1e-5));
	float largest = max(unit.x, max(unit.y, unit.z));
	return largest > 1.0 ? center + offset / largest : history;
}
#endif

void main() {
	ivec2 px = ivec2(gl_FragCoord.xy);
	vec3 current = texelFetch(colortex0, px, 0).rgb;

#ifdef TEMPORAL_AA
	vec2 size = vec2(viewWidth, viewHeight);
	ivec2 maxPx = ivec2(size) - 1;

	// Neighbourhood statistics, using the closest depth to keep edges from trailing.
	vec3 m1 = vec3(0.0);
	vec3 m2 = vec3(0.0);
	float closest = 1.0;
	ivec2 closestPx = px;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			ivec2 p = clamp(px + ivec2(x, y), ivec2(0), maxPx);
			vec3 c = toYCoCg(compress(texelFetch(colortex0, p, 0).rgb));
			m1 += c;
			m2 += c * c;
			if (abs(x) + abs(y) <= 1) {
				float d = texelFetch(depthtex0, p, 0).r;
				if (d < closest) {
					closest = d;
					closestPx = p;
				}
			}
		}
	}
	vec3 mean = m1 / 9.0;
	vec3 deviation = sqrt(max(m2 / 9.0 - mean * mean, vec3(0.0)));

	vec2 uv = (vec2(closestPx) + 0.5) / size;
	int materialClass = unpackMaterialClass(texelFetch(colortex3, px, 0).b);
	vec2 velocity = vec2(0.0);
	bool isHand = closest < 1.0 && materialClass == MAT_HAND;
	if (!isHand) {
		vec3 feet = viewToFeet(viewFromScreen(uv, closest));
		velocity = reprojectFeet(feet).xy - uv;
	}
	vec2 historyUv = texCoord + velocity;

	// Pixels revealed at the screen edge have no history at all. Their single frame of shadow
	// and reflection noise is softened with the neighbourhood, until history has built up.
	vec3 result = expand(max(fromYCoCg(mix(mean, toYCoCg(compress(current)), 0.45)), vec3(0.0)));
	if (historyUv.x > 0.0 && historyUv.y > 0.0 && historyUv.x < 1.0 && historyUv.y < 1.0) {
		vec3 historyC = toYCoCg(historyCatmullRom(historyUv, size));
		float motion = length(velocity * size);
		// While the view stands still, nothing can trail, so the box may be wider and the
		// history longer. That keeps the per-frame noise of shadows and reflections from
		// pushing the history around, which shows as a faint flicker.
		float settled = 1.0 - saturate(motion * 4.0);
		float gamma = mix(1.25, 0.9, saturate(motion * 0.25)) + 0.35 * settled;
		vec3 clipped = clipToBox(historyC, mean, deviation * gamma + vec3(0.0005));

		vec3 currentC = toYCoCg(compress(current));
		float blend = isHand ? 0.35 : mix(0.075, 0.22, saturate(motion * 0.2)) - 0.02 * settled;
		// History that needed a large correction no longer belongs to this surface.
		float correction = length(clipped - historyC) / max(clipped.x + 0.02, 0.02);
		blend = saturate(blend + correction * 0.2);
		result = expand(max(fromYCoCg(mix(clipped, currentC, blend)), vec3(0.0)));
	}
	if (any(isnan(result)) || any(isinf(result))) result = current;
	outHistory = vec4(clamp(result, vec3(0.0), vec3(400.0)), 1.0);
#else
	outHistory = vec4(current, 1.0);
#endif
}
#endif
