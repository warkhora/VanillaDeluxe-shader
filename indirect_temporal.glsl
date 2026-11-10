// VanillaDeluxe - temporal accumulation of the half resolution indirect trace.
// History is rejected when the depth or normal it was traced at no longer matches the
// reprojected point. colortex14 holds: linear depth, accumulated frames, second moment of the
// luminance, packed normal. The moment gives the spatial denoiser the noise level of each pixel.
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
uniform sampler2D colortex3;
uniform sampler2D colortex6;
uniform sampler2D colortex10;
uniform sampler2D colortex14;

/* RENDERTARGETS: 10,14 */
layout(location = 0) out vec4 outIndirect;
layout(location = 1) out vec4 outDepthHistory;

void main() {
	ivec2 halfPx = ivec2(gl_FragCoord.xy);
	vec2 viewSize = vec2(viewWidth, viewHeight);
	ivec2 fullPx = halfPx * 2;
	float depth = texelFetch(depthtex0, fullPx, 0).r;
	vec4 current = texelFetch(colortex6, halfPx, 0);
	float linearZ = depth >= 1.0 ? 1e5 : linearDepth(depth);
	vec2 octNormal = texelFetch(colortex3, fullPx, 0).rg;
	float currentLum = luminance(current.rgb);

#ifdef USE_INDIRECT
	vec2 uv = (vec2(fullPx) + 0.5) / viewSize;
	vec3 feet = viewToFeet(viewFromScreen(uv, depth));
	vec3 previous = reprojectFeet(feet);
	float frames = 0.0;
	vec4 result = current;
	float moment = currentLum * currentLum;

	bool inside = previous.x > 0.0 && previous.y > 0.0 && previous.x < 1.0 && previous.y < 1.0;
	if (inside && depth < 1.0) {
		vec4 history = texelFetch(colortex14, ivec2(previous.xy * viewSize * 0.5), 0);
		float tolerance = 0.06 * previous.z + 0.12;
		bool sameSurface = abs(history.r - previous.z) < tolerance
			&& dot(decodeNormal(octNormal), unpackNormalFloat(history.a)) > 0.7;
		if (sameSurface) {
			// History is kept for about a third of a second, and never for fewer than 24 frames.
			// A longer history settles the noise, a shorter one follows a torch that is placed.
			float maxFrames = clamp(floor(0.3 / max(frameTime, 1e-3)), 24.0, 64.0);
			frames = min(history.g + 1.0, maxFrames);
			// Each texel of this buffer was traced at the lower left full resolution pixel of its
			// 2 x 2 block. Sampling at that point, and not at the texel centre, keeps the history
			// from creeping a quarter texel per frame, which smeared light into the shadows.
			vec4 accumulated = texture(colortex10, previous.xy + 0.5 / viewSize);
			// A single bright ray must not stand out for the next twenty frames.
			float limit = luminance(accumulated.rgb) * 6.0 + 0.5;
			if (frames > 2.0 && currentLum > limit) {
				current.rgb *= limit / currentLum;
				currentLum = limit;
			}
			float alpha = 1.0 / (frames + 1.0);
			result = mix(accumulated, current, alpha);
			moment = mix(history.b, currentLum * currentLum, alpha);
		}
	}
	outIndirect = max(result, vec4(0.0));
	outDepthHistory = vec4(linearZ, frames, moment, packNormalFloat(octNormal));
#else
	outIndirect = current;
	outDepthHistory = vec4(linearZ, 0.0, 0.0, packNormalFloat(octNormal));
#endif
}
#endif
