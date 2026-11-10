// VanillaDeluxe - overlays blended straight into the albedo buffer:
// the block breaking animation and the enchantment glint.
#include "/lib/settings.glsl"
#include "/lib/common.glsl"

#ifdef VSH
out vec2 vTexCoord;
out vec4 vColor;
void main() {
	vTexCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	vColor = gl_Color;
	gl_Position = gl_ProjectionMatrix * (gl_ModelViewMatrix * gl_Vertex);
	gl_Position.xy += taaJitter() * gl_Position.w;
}
#endif

#ifdef FSH
in vec2 vTexCoord;
in vec4 vColor;
uniform sampler2D gtexture;
uniform float alphaTestRef;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outColor;

void main() {
	vec4 c = texture(gtexture, vTexCoord) * vColor;
	if (c.a < max(alphaTestRef, 0.004)) discard;
#ifdef GB_GLINT
	outColor = vec4(toLinear(c.rgb) * 0.65, c.a);
#else
	outColor = c;
#endif
}
#endif
