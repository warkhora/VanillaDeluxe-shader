// VanillaDeluxe - vanilla sky objects. The sky colour itself comes from the sky LUT,
// so only stars and the moon are kept here. They are drawn to colortex0 and added
// to the atmosphere by the deferred lighting pass.
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
uniform int renderStage;
#ifdef GB_SKYTEXTURED
uniform sampler2D gtexture;
#endif

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outColor;

void main() {
#ifdef GB_SKYTEXTURED
	if (renderStage == MC_RENDER_STAGE_SUN) discard;
#if DIM_ID != 0
	discard;
#endif
	vec4 c = texture(gtexture, vTexCoord) * vColor;
	outColor = vec4(toLinear(c.rgb) * c.a * 1.6, 1.0);
#else
	if (renderStage != MC_RENDER_STAGE_STARS) discard;
#if DIM_ID != 0
	discard;
#endif
	outColor = vec4(toLinear(vColor.rgb) * vColor.a * 0.9, 1.0);
#endif
}
#endif
