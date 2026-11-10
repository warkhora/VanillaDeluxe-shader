// VanillaDeluxe - G-buffer writer for all opaque geometry.
// Variants are selected by the stub that includes this file:
// GB_TERRAIN, GB_BLOCK, GB_ENTITY, GB_HAND, GB_BASIC, GB_CLOUDS, GB_EMISSIVE
#include "/lib/settings.glsl"
#include "/lib/common.glsl"
#include "/lib/material.glsl"

#if defined GB_TERRAIN || defined GB_BLOCK || defined GB_ENTITY || defined GB_HAND
#define GB_HAS_PBR 1
#endif

// ========================================================================== //
#ifdef VSH

out vec2 vTexCoord;
out vec2 vLmCoord;
out vec4 vColor;
out vec3 vViewPos;
out vec3 vNormal;
flat out int vBlockId;

#ifdef GB_HAS_PBR
in vec4 at_tangent;
out vec4 vTangent;
#endif

#ifdef GB_TERRAIN
in vec2 mc_Entity;
in vec2 mc_midTexCoord;
in vec4 at_midBlock;
out vec2 vTileMid;
out vec2 vTileHalf;
flat out float vBlockLight;
#endif

#ifdef GB_BLOCK
uniform int blockEntityId;
#endif

#if defined GB_ENTITY && DIM_ID == 1 && defined END_CRYSTAL_RAYS
#define CRYSTAL_WRITER 1
uniform int entityId;
#include "/lib/crystals.glsl"
#endif

void main() {
	vTexCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	vLmCoord = saturate(((gl_TextureMatrix[1] * gl_MultiTexCoord1).xy - 0.03125) * 1.06667);
	vColor = gl_Color;
	vBlockId = -1;

	vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;

#ifdef GB_TERRAIN
	vBlockId = int(mc_Entity.x + 0.5);
	vTileMid = mc_midTexCoord;
	vTileHalf = abs(vTexCoord - mc_midTexCoord);
	vBlockLight = at_midBlock.w / 15.0;

	vec3 sway = vec3(0.0);
	vec3 worldPos = viewToFeet(viewPos.xyz) + cameraPosition;
#ifdef WAVING_PLANTS
	if (vBlockId == ID_PLANT || vBlockId == ID_PLANT_LOWER) {
		if (at_midBlock.y < 0.0) sway = windOffset(worldPos, vBlockId == ID_PLANT ? 0.055 : 0.03);
	} else if (vBlockId == ID_PLANT_UPPER) {
		sway = windOffset(worldPos, at_midBlock.y < 0.0 ? 0.09 : 0.03);
	}
#endif
#ifdef WAVING_LEAVES
	if (vBlockId == ID_LEAVES) {
		sway = windOffset(worldPos, 0.022);
	} else if (vBlockId == ID_VINES) {
		sway = windOffset(worldPos, 0.04);
	}
#endif
	if (vLmCoord.y > 0.05) viewPos.xyz += mat3(gbufferModelView) * sway * smoothstep(0.05, 0.5, vLmCoord.y);
#endif

#ifdef GB_BLOCK
	vBlockId = blockEntityId;
#endif
#ifdef CRYSTAL_WRITER
	if (entityId == ID_END_CRYSTAL) recordCrystal(viewToFeet(viewPos.xyz));
#endif

	vViewPos = viewPos.xyz;
	vNormal = normalize(gl_NormalMatrix * gl_Normal);
#ifdef GB_HAS_PBR
	vTangent = vec4(normalize(gl_NormalMatrix * at_tangent.xyz), at_tangent.w);
#endif

	gl_Position = gl_ProjectionMatrix * viewPos;
	gl_Position.xy += taaJitter() * gl_Position.w;
}

#endif
// ========================================================================== //
#ifdef FSH

in vec2 vTexCoord;
in vec2 vLmCoord;
in vec4 vColor;
in vec3 vViewPos;
in vec3 vNormal;
flat in int vBlockId;

#ifndef GB_BASIC
uniform sampler2D gtexture;
#endif
uniform float alphaTestRef;

#ifdef GB_HAS_PBR
in vec4 vTangent;
uniform sampler2D normals;
uniform sampler2D specular;
#endif

#ifdef GB_ENTITY
uniform vec4 entityColor;
uniform int entityId;
#endif

#ifdef GB_TERRAIN
in vec2 vTileMid;
in vec2 vTileHalf;
flat in float vBlockLight;
uniform ivec2 atlasSize;
uniform sampler2D noisetex;
uniform int biome_precipitation;
#include "/lib/weather.glsl"
#include "/lib/weather_map.glsl"
#include "/lib/parallax.glsl"
#include "/lib/surface_detail.glsl"
#endif

/* RENDERTARGETS: 0,1,2,3 */
layout(location = 0) out vec4 outAlbedo;
layout(location = 1) out vec4 outNormalLight;
layout(location = 2) out vec4 outMaterial;
layout(location = 3) out vec4 outGeometry;

#ifdef GB_TERRAIN
float textureHeightAt(vec2 uv, vec2 ddx, vec2 ddy) {
	return dot(textureGrad(gtexture, uv, ddx, ddy).rgb, vec3(0.299, 0.587, 0.114));
}
// Surface detail derived from the brightness of the vanilla texture.
vec3 generateNormal(vec2 uv, vec2 ddx, vec2 ddy, float strength) {
	vec2 texel = 1.0 / vec2(atlasSize);
	vec2 low = vTileMid - vTileHalf + texel * 0.5;
	vec2 high = vTileMid + vTileHalf - texel * 0.5;
	float center = textureHeightAt(uv, ddx, ddy);
	float right = textureHeightAt(clamp(uv + vec2(texel.x, 0.0), low, high), ddx, ddy);
	float below = textureHeightAt(clamp(uv + vec2(0.0, texel.y), low, high), ddx, ddy);
	return normalize(vec3((center - right) * strength, (center - below) * strength, 1.0));
}
#endif

void main() {
	vec3 geomNormal = normalize(vNormal);
	vec3 shadingNormal = geomNormal;
	float dist = length(vViewPos);
	int materialClass = MAT_GENERIC;
	float parallaxLight = 1.0;
	float vanillaAo = 1.0;
	vec2 uv = vTexCoord;

#ifdef GB_BASIC
	vec4 base = vColor;
	if (base.a < 0.01) discard;
	outAlbedo = vec4(toLinear(base.rgb), base.a);
	outNormalLight = vec4(encodeNormal(mat3(gbufferModelView) * vec3(0.0, 1.0, 0.0)), vLmCoord);
	outMaterial = vec4(0.1, 0.04, 0.0, 0.0);
	outGeometry = vec4(encodeNormal(geomNormal), packMaterial(MAT_GENERIC, 1.0), 1.0);
	return;
#else

#ifdef GB_HAS_PBR
	// Build the tangent frame. Geometry without tangents falls back to the vertex normal.
	mat3 tbn = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), geomNormal);
	bool hasTangent = dot(vTangent.xyz, vTangent.xyz) > 0.01;
	if (hasTangent) {
		vec3 tangent = normalize(vTangent.xyz - geomNormal * dot(geomNormal, vTangent.xyz));
		vec3 bitangent = cross(tangent, geomNormal) * (vTangent.w < 0.0 ? -1.0 : 1.0);
		tbn = mat3(tangent, bitangent, geomNormal);
	}
#endif

#if defined GB_TERRAIN && defined PARALLAX_OCCLUSION && PBR_FORMAT != 0
	float pomFade = 1.0 - smoothstep(float(POM_DISTANCE) * 0.75, float(POM_DISTANCE), dist);
	vec2 pomDx = dFdx(vTexCoord);
	vec2 pomDy = dFdy(vTexCoord);
	if (pomFade > 0.001 && hasTangent && vTileHalf.x > 0.0 && vTileHalf.y > 0.0) {
		vec3 tangentEye = normalize(-vViewPos * tbn);
		float hitDepth = 0.0;
		uv = parallaxOcclusion(vTexCoord, tangentEye, vTileMid, vTileHalf, pomDx, pomDy, pomFade, hitDepth);
#ifdef POM_SELF_SHADOW
		vec3 tangentLight = normalize(shadowLightPosition) * tbn;
		parallaxLight = parallaxShadow(uv, hitDepth, tangentLight, vTileMid, vTileHalf, pomDx, pomDy, pomFade);
#endif
	}
#endif

#ifdef GB_TERRAIN
	vec2 sampleDx = dFdx(vTexCoord);
	vec2 sampleDy = dFdy(vTexCoord);
	vec4 tex = textureGrad(gtexture, uv, sampleDx, sampleDy);
	// With separateAo the vertex alpha is ambient occlusion rather than opacity.
	vec3 gammaColor = tex.rgb * vColor.rgb;
	float alpha = tex.a;
	vanillaAo = vColor.a;
#else
	vec4 tex = texture(gtexture, uv);
	vec3 gammaColor = tex.rgb * vColor.rgb;
	float alpha = tex.a * vColor.a;
#endif

	if (alpha < max(alphaTestRef, 0.004)) discard;

#ifdef GB_ENTITY
	gammaColor = mix(gammaColor, entityColor.rgb, entityColor.a);
	materialClass = MAT_ENTITY;
#endif
#ifdef GB_HAND
	materialClass = MAT_HAND;
#endif

	vec3 albedo = toLinear(gammaColor);
	float lum = dot(gammaColor, vec3(0.299, 0.587, 0.114));
	float smoothness = 0.14;
	float f0Raw = 0.04;
	float emission = 0.0;
	float subsurfaceRaw = 0.0;
	float porosity = 0.5;

#ifdef GB_TERRAIN
	if (isFoliageId(vBlockId)) materialClass = MAT_FOLIAGE;
	integratedMaterial(vBlockId, lum, vBlockLight, smoothness, f0Raw, emission, subsurfaceRaw);
#endif
#ifdef GB_BLOCK
	if (vBlockId == ID_END_PORTAL) emission = 1.0;
#endif
#ifdef GB_ENTITY
	// The bright core and frame of an End crystal glow.
	if (entityId == 20000) emission = 0.35 + 0.65 * smoothstep(0.3, 0.85, lum);
#endif
#ifdef GB_EMISSIVE
	emission = 1.0;
	materialClass = MAT_UNLIT;
#endif
#ifdef GB_CLOUDS
	materialClass = MAT_CLOUD;
#ifdef VOLUMETRIC_CLOUDS
	discard;
#endif
#endif

#ifdef GB_HAS_PBR
#if PBR_FORMAT == 1
	vec4 specularMap = texture(specular, uv);
	if (specularMap.r + specularMap.g + specularMap.b + specularMap.a > 0.002) {
		smoothness = specularMap.r;
		f0Raw = specularMap.g;
		subsurfaceRaw = specularMap.b;
		porosity = specularMap.b < 0.2549 ? specularMap.b / 0.25098 : 0.0;
		emission = specularMap.a < 0.999 ? specularMap.a * 1.003937 : 0.0;
	}
#elif PBR_FORMAT == 2
	vec4 specularMap = texture(specular, uv);
	if (specularMap.r + specularMap.g + specularMap.b > 0.002) {
		smoothness = specularMap.r;
		f0Raw = specularMap.g > 0.5 ? 1.0 : 0.04;
		emission = specularMap.b;
		subsurfaceRaw = 0.0;
	}
#endif

	bool hasNormalDetail = false;
#ifdef NORMAL_MAPPING
#if PBR_FORMAT != 0
	vec4 normalMap = texture(normals, uv);
	if (hasTangent && (normalMap.r > 0.002 || normalMap.g > 0.002)) {
		vec2 xy = normalMap.rg * 2.0 - 1.0;
		// labPBR stores material AO in the blue channel. seusPBR stores normal z there.
#if PBR_FORMAT == 1
		vanillaAo *= normalMap.b;
#endif
		if (abs(xy.x) > 0.008 || abs(xy.y) > 0.008) {
			hasNormalDetail = true;
			vec3 tangentNormal = vec3(xy, sqrt(max(1.0 - dot(xy, xy), 0.0)));
			shadingNormal = normalize(tbn * tangentNormal);
		}
	}
#endif
#endif

#ifdef GB_TERRAIN
#ifdef GENERATED_NORMALS
	if (!hasNormalDetail && hasTangent && atlasSize.x > 0 && materialClass != MAT_FOLIAGE && dist < 40.0) {
		// Polished surfaces show every normal in their reflection, so they get far less of it.
		float glossFade = 1.0 - smoothstep(0.25, 0.65, smoothness) * 0.92;
		float strength = (1.0 - smoothstep(24.0, 40.0, dist)) * float(GENERATED_NORMAL_STRENGTH) / 100.0 * 1.4 * glossFade;
		shadingNormal = normalize(tbn * generateNormal(uv, sampleDx, sampleDy, strength));
	}
#endif
#endif
#endif

#ifdef GB_TERRAIN
	if (vBlockId == ID_LAVA) {
		// The class lets the lighting pass apply the brightness slider beyond the 8-bit range.
		materialClass = MAT_LAVA;
		vec3 lavaPos = viewToFeet(vViewPos) + cameraPosition;
		emission *= lavaPulse(lavaPos) / LAVA_EMISSION_RANGE;
		vec3 lavaNormal = mat3(gbufferModelViewInverse) * shadingNormal;
		shadingNormal = normalize(mat3(gbufferModelView) * perturbWorldNormal(lavaNormal, lavaPos + vec3(frameTimeCounter * 0.05, 0.0, 0.0), 0.016, 0.45));
	}

	// Plants are thin sheets. An upward normal makes their lighting soft and uniform.
	if (vBlockId == ID_PLANT || vBlockId == ID_PLANT_LOWER || vBlockId == ID_PLANT_UPPER) {
		vec3 up = mat3(gbufferModelView) * vec3(0.0, 1.0, 0.0);
		shadingNormal = up;
		geomNormal = up;
	}

#ifdef WET_SURFACES
	vec3 wetNormal = mat3(gbufferModelViewInverse) * geomNormal;
	vec3 wetFeet = viewToFeet(vViewPos);
	// Only where rain can fall: nothing under a roof gets wet, however much sky light reaches it.
	float sky = wetness > 0.002 && vLmCoord.y > 0.2 && biome_precipitation == 1 ? weatherExposure(wetFeet, wetNormal, vLmCoord.y) : 0.0;
	if (sky > 0.0) {
		vec3 worldNormal = wetNormal;
		vec3 worldPos = wetFeet + cameraPosition;
		float upFacing = saturate(worldNormal.y);
		float puddle = texture(noisetex, worldPos.xz * 0.0035).r * 0.65 + texture(noisetex, worldPos.xz * 0.013).g * 0.35;
#ifdef DYNAMIC_PUDDLES
		// Water runs into dips first: a block with higher ground on every side fills with the
		// first rain, flat ground follows as the rain goes on. After the rain the puddles shrink
		// again, faster while the sun shines on them.
		float basin = 0.0;
#ifdef USE_WEATHER_MAP
		basin = weatherBasin(wetFeet + worldNormal * 0.5);
#endif
		float sunshine = saturate(worldSunDir().y * 2.0) * (1.0 - rainStrength);
		float level = wetness * (1.0 - 0.45 * sunshine) * float(PUDDLE_AMOUNT) / 100.0;
		float shape = puddle * 0.75 + basin * 0.9;
		float pool = smoothstep(1.02 - level * 0.62, 1.10 - level * 0.62, shape) * upFacing;
#else
		float pool = smoothstep(0.42, 0.56, puddle) * upFacing;
#endif
		float wet = wetness * sky * saturate(0.40 + pool);
		albedo *= mix(1.0, mix(0.86, 0.58, porosity), wet);
		smoothness = mix(smoothness, mix(0.72, 0.96, pool), wet * (0.35 + 0.65 * upFacing));
		f0Raw = max(f0Raw, 0.02 * wet);
		shadingNormal = normalize(mix(shadingNormal, geomNormal, pool * wet));
#if WEATHER_SPLASH_QUALITY > 0
		// While it rains, drops ring the puddles like the water pass does, and to a lesser degree
		// the thin film of water on the rest of the ground. The rings show in the reflections.
		if (rainStrength > 0.01 && upFacing > 0.5) {
			vec2 ripple = rainRipples(worldPos.xz, length(vViewPos)) * rainStrength * sky * mix(0.35, 1.0, pool) * wetness;
			vec3 rippled = normalize(mat3(gbufferModelViewInverse) * shadingNormal + vec3(-ripple.x, 0.0, -ripple.y));
			shadingNormal = normalize(mat3(gbufferModelView) * rippled);
		}
#endif
	}
#endif
#endif

	outAlbedo = vec4(albedo, alpha);
	outNormalLight = vec4(encodeNormal(shadingNormal), vLmCoord);
	outMaterial = vec4(smoothness, f0Raw, emission, subsurfaceRaw);
	outGeometry = vec4(encodeNormal(geomNormal), packMaterial(materialClass, parallaxLight), vanillaAo);
#endif
}

#endif
