// VanillaDeluxe - temporal filter for the half resolution volumetrics.
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
uniform sampler2D colortex9;
uniform sampler2D colortex12;

/* RENDERTARGETS: 12 */
layout(location = 0) out vec4 outFog;

void main() {
	ivec2 px = ivec2(gl_FragCoord.xy);
	ivec2 bounds = ivec2(viewWidth, viewHeight) / 2 - 1;
	vec4 current = texelFetch(colortex9, px, 0);
	// With the checkerboard, pixels that were not marched this frame have alpha -1. They take the
	// average of their marched neighbours, and lean on history more.
	bool marched = current.a >= 0.0;

	vec4 low = vec4(1e5);
	vec4 high = vec4(-1e5);
	vec4 neighbourSum = vec4(0.0);
	float neighbours = 0.0;
	if (marched) {
		low = current;
		high = current;
	}
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			if (x == 0 && y == 0) continue;
			vec4 c = texelFetch(colortex9, clamp(px + ivec2(x, y), ivec2(0), bounds), 0);
			if (c.a < 0.0) continue;
			low = min(low, c);
			high = max(high, c);
			if (abs(x) + abs(y) == 1) {
				neighbourSum += c;
				neighbours += 1.0;
			}
		}
	}
	if (!marched) current = neighbours > 0.0 ? neighbourSum / neighbours : vec4(0.0, 0.0, 0.0, 1.0);

	float depth = texelFetch(depthtex0, px * 2, 0).r;
	vec3 feet = viewToFeet(viewFromScreen(texCoord, depth));
	vec2 previous = reprojectFeet(feet).xy;

	vec4 result = current;
	if (previous.x > 0.0 && previous.y > 0.0 && previous.x < 1.0 && previous.y < 1.0) {
		vec4 history = texture(colortex12, previous);
		vec4 margin = (high - low) * 0.5 + vec4(0.002);
		history = clamp(history, low - margin, high + margin);
		// A long history while the view stands still settles the noise of thin smoke and haze.
		// In motion it is shorter, so fog does not trail behind the camera.
		float motion = length((previous - texCoord) * vec2(viewWidth, viewHeight));
		float blend = mix(0.05, 0.12, saturate(motion * 0.5));
		// A filled-in pixel is an estimate. History is worth more there.
		if (!marched) blend *= 0.5;
		result = mix(history, current, blend);
	}
	outFog = max(result, vec4(0.0));
}
#endif
