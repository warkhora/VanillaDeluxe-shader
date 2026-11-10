// VanillaDeluxe - bloom. The mip chain of the resolved image is read with a bicubic
// filter, which hides the box shape of the mips for a small number of texture reads.
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

uniform sampler2D colortex7;

const bool colortex7MipmapEnabled = true;

/* RENDERTARGETS: 8 */
layout(location = 0) out vec4 outBloom;

vec3 bicubicLod(vec2 uv, float lod) {
	vec2 size = vec2(viewWidth, viewHeight) / pow(2.0, lod);
	vec2 st = uv * size - 0.5;
	vec2 f = fract(st);
	st -= f;
	vec2 f2 = f * f;
	vec2 f3 = f2 * f;
	vec2 w0 = (1.0 - f) * (1.0 - f) * (1.0 - f) / 6.0;
	vec2 w1 = (4.0 - 6.0 * f2 + 3.0 * f3) / 6.0;
	vec2 w3 = f3 / 6.0;
	vec2 w2 = 1.0 - w0 - w1 - w3;
	vec2 s0 = w0 + w1;
	vec2 s1 = w2 + w3;
	vec2 t0 = (st - 1.0 + w1 / s0 + 0.5) / size;
	vec2 t1 = (st + 1.0 + w3 / s1 + 0.5) / size;
	return (textureLod(colortex7, vec2(t0.x, t0.y), lod).rgb * s0.x + textureLod(colortex7, vec2(t1.x, t0.y), lod).rgb * s1.x) * s0.y
		+ (textureLod(colortex7, vec2(t0.x, t1.y), lod).rgb * s0.x + textureLod(colortex7, vec2(t1.x, t1.y), lod).rgb * s1.x) * s1.y;
}

void main() {
	vec3 sum = vec3(0.0);
	float total = 0.0;
	float weight = 1.0;
	for (int lod = 2; lod <= 8; lod++) {
		sum += bicubicLod(texCoord, float(lod)) * weight;
		total += weight;
		weight *= 0.82;
	}
	outBloom = vec4(max(sum / total, vec3(0.0)), 1.0);
}
#endif
