// VanillaDeluxe - forward shading for everything drawn after the deferred pass.
// Colour is written premultiplied to colortex4. Water and glass also write their
// normal to colortex5, which composite2 uses for refraction and reflection.
// Variants: FW_WATER, FW_TRANSLUCENT, FW_PARTICLE, FW_WEATHER, FW_LIGHTNING, FW_BEACON
#include "/lib/settings.glsl"
#include "/lib/common.glsl"

// ========================================================================== //
#ifdef VSH

out vec2 vTexCoord;
out vec2 vLmCoord;
out vec4 vColor;
out vec3 vViewPos;
out vec3 vNormal;
flat out int vBlockId;

#ifdef FW_WATER
in vec2 mc_Entity;
#endif
#ifdef FW_WEATHER
uniform int biome_precipitation;
#include "/lib/weather.glsl"
#endif

void main() {
	vTexCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	vLmCoord = saturate(((gl_TextureMatrix[1] * gl_MultiTexCoord1).xy - 0.03125) * 1.06667);
	vColor = gl_Color;
	vBlockId = -1;
#ifdef FW_WATER
	vBlockId = int(mc_Entity.x + 0.5);
#endif
	vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;
#ifdef FW_WEATHER
	// Wind blows the weather sideways: the columns of rain and snow lean with it, more in a storm,
	// and snow also swirls. Higher points are moved further upwind, so everything falls at a slant.
	vec3 weatherFeet = viewToFeet(viewPos.xyz);
	vec3 weatherWorld = weatherFeet + cameraPosition;
	vec2 wind = weatherWindDirection() * weatherGust(weatherWorld);
	if (biome_precipitation == 2) {
		float drift = float(SNOW_WIND_DRIFT) / 100.0;
		float t = frameTimeCounter;
		vec2 swirl = vec2(sin(t * 1.3 + weatherWorld.x * 0.7 + weatherWorld.y * 0.45), cos(t * 1.1 + weatherWorld.z * 0.6 + weatherWorld.y * 0.5));
		weatherFeet.xz -= wind * weatherFeet.y * 0.32 * drift;
		weatherFeet.xz += swirl * 0.28 * drift;
	} else {
		weatherFeet.xz -= wind * weatherFeet.y * (0.06 + 0.20 * thunderStrength);
	}
	viewPos.xyz = feetToView(weatherFeet);
#endif
	vViewPos = viewPos.xyz;
	vNormal = normalize(gl_NormalMatrix * gl_Normal);
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

uniform sampler2D gtexture;
uniform float alphaTestRef;

#include "/lib/sky.glsl"
#include "/lib/shadow.glsl"
#include "/lib/brdf.glsl"
#include "/lib/material.glsl"

#ifdef FW_WATER
#include "/lib/water.glsl"
uniform sampler2D depthtex1;
uniform sampler2D noisetex;
#include "/lib/surface_detail.glsl"
#endif

#if defined FW_PARTICLE && defined VOLUMETRIC_SMOKE
uniform sampler2D noisetex;
#include "/lib/rt_light.glsl"
#include "/lib/smoke.glsl"
#endif

#if defined FW_WATER || defined FW_WEATHER || defined FW_PARTICLE
uniform int biome_precipitation;
#include "/lib/weather.glsl"
#include "/lib/weather_map.glsl"
#endif
#if defined FW_WEATHER && defined USE_RT_LIGHT
#include "/lib/rt_light.glsl"
#endif

#ifdef FW_WATER
/* RENDERTARGETS: 4,5,15 */
layout(location = 0) out vec4 outColor;
layout(location = 1) out vec4 outSurface;
layout(location = 2) out vec4 outFilter;
#elif defined FW_WEATHER && defined RAIN_REFRACTION
/* RENDERTARGETS: 4,16 */
layout(location = 0) out vec4 outColor;
layout(location = 1) out vec4 outRefraction;
#else
/* RENDERTARGETS: 4 */
layout(location = 0) out vec4 outColor;
#endif

vec3 ambientLighting(vec3 worldNormal) {
	vec3 ambient = skyAmbient(worldNormal, readAmbientUp(), readAmbientSide());
#ifdef HAS_SKYLIGHT
	ambient = applySkyOcclusion(ambient, vLmCoord.y);
#endif
	float block = vLmCoord.x * vLmCoord.x * vLmCoord.x;
	vec3 blockColor = vec3(1.0, 0.60, 0.28) * block * float(BLOCKLIGHT_STRENGTH) / 100.0;
	return ambient + blockColor + vec3(0.012, 0.013, 0.016) * float(MIN_LIGHT) / 100.0;
}

void main() {
#ifdef FW_LIGHTNING
	outColor = vec4(vColor.rgb * vColor.a * 16.0, vColor.a);
#else

	vec4 tex = texture(gtexture, vTexCoord);

#ifdef FW_BEACON
	// Both layers of the beam add light. The outer layer is faint because its alpha is low.
	float beamAlpha = tex.a * vColor.a;
	if (beamAlpha < 0.004) discard;
	outColor = vec4(toLinear(tex.rgb * vColor.rgb) * beamAlpha * 5.0, 0.0);
#else

#ifdef FW_WEATHER
	float weatherAlpha = tex.a * vColor.a;
#ifdef RAIN_REFRACTION
	// The edges of a streak, where its alpha changes, are where a drop bends the light the most.
	// The slope has to be taken before the discard below.
	vec2 alphaSlope = vec2(dFdx(weatherAlpha), dFdy(weatherAlpha));
#endif
	// Snow is drawn by the final pass, in real depth. The vanilla flakes are dropped.
	if (biome_precipitation == 2) discard;
	if (weatherAlpha < 0.02) discard;
	bool isSnow = false;
	vec3 weatherDir = normalize(mat3(gbufferModelViewInverse) * vViewPos);
	float weatherSky = 1.0;
#ifdef HAS_SKYLIGHT
	weatherSky = 0.15 + 0.85 * vLmCoord.y;
#endif
	vec3 skyLight = readAmbientUp() * weatherSky;
	vec3 sunLight = readLightColor() * weatherSky;
	float towardsLight = dot(weatherDir, worldLightDir());

	// Torches and lava light the weather around them, in their own colour with ray tracing.
	float blockLevel = vLmCoord.x;
	float blockCurve = blockLevel * blockLevel * (0.22 + 1.05 * blockLevel * blockLevel);
	vec3 blockLight = vec3(1.0, 0.52, 0.24) * blockCurve * 1.35 * float(BLOCKLIGHT_STRENGTH) / 100.0;
#ifdef USE_RT_LIGHT
	if (blockLevel > 0.05) {
		vec3 weatherFeetPos = viewToFeet(vViewPos);
		vec4 lightNoise = vec4(
			cycleNoise(gl_FragCoord.xy + vec2(17.0, 5.0), 8, NOISE_STEP_A),
			cycleNoise(gl_FragCoord.xy + vec2(3.0, 41.0), 8, NOISE_STEP_B),
			cycleNoise(gl_FragCoord.xy + vec2(29.0, 11.0), 8, NOISE_STEP_C),
			cycleNoise(gl_FragCoord.xy + vec2(7.0, 23.0), 8, NOISE_STEP_D));
		vec3 traced = rtBlockLight(weatherFeetPos, -weatherDir, true, lightNoise, false);
		blockLight = mix(blockLight, traced, rtRangeFade(weatherFeetPos));
	}
#endif

	if (isSnow) {
		// Snowflakes are small white scatterers. They light up brightly next to a torch, which makes
		// them glitter around light sources at night, and glow faintly towards the sun or moon.
		vec3 flakeLight = skyLight * 0.95 + sunLight * (0.10 + 0.25 * phaseHG(towardsLight, 0.45)) + blockLight * 1.5;
		float flakeOpacity = saturate(weatherAlpha * 0.85);
		outColor = vec4(flakeLight * flakeOpacity, flakeOpacity * 0.85);
	} else {
		// A raindrop is a small lens. It is nearly invisible, except where it catches light: the
		// sky above it, the sun or moon behind it, and the torches around it.
		vec3 dropLight = skyLight * 0.65 + sunLight * (0.03 + 0.55 * phaseHG(towardsLight, 0.78)) + blockLight * 1.1;
		float dropOpacity = saturate(weatherAlpha * 0.20 * float(RAIN_OPACITY) / 100.0);
		outColor = vec4(dropLight * dropOpacity, dropOpacity * 0.30);
	}
#ifdef RAIN_REFRACTION
	// The final pass bends the image behind each streak by this offset, in screen units.
	vec2 bend = isSnow ? vec2(0.0) : -alphaSlope * 4.0 / vec2(viewWidth, viewHeight);
	outRefraction = vec4(bend, isSnow ? 0.0 : weatherAlpha, 1.0);
#endif
#else

	vec3 gammaColor = tex.rgb * vColor.rgb;
#ifdef FW_WATER
	// separateAo moves ambient occlusion into the vertex alpha on terrain.
	float alpha = tex.a;
#else
	float alpha = tex.a * vColor.a;
#endif
#if defined FW_WATER && defined GLASS_REFLECTIONS
	// The clear pixels of a window are invisible in the texture, but they still reflect.
	if (alpha < max(alphaTestRef, 0.004) && vBlockId != ID_GLASS) discard;
#else
	if (alpha < max(alphaTestRef, 0.004)) discard;
#endif

#if defined FW_PARTICLE && defined USE_WEATHER_MAP
	// Vanilla rain splashes. Iris can only switch them off together with the rain itself, which
	// this pack draws from the vanilla columns. A splash is recognised as a pale, bluish particle
	// sitting just on top of the highest block of its column while it rains.
	if (rainStrength > 0.01 && biome_precipitation == 1) {
		vec3 particleColor = tex.rgb * vColor.rgb;
		bool bluish = particleColor.b >= particleColor.r && particleColor.b > 0.25;
		ivec3 cell = weatherCell(viewToFeet(vViewPos));
		int top;
		if (bluish && weatherInMap(cell.xz) && weatherColumnTop(cell.xz, top) && cell.y >= top && cell.y <= top + 1) discard;
	}
#endif

#if defined FW_PARTICLE && defined VOLUMETRIC_SMOKE
	// Vanilla smoke is a flat grey card. Above a torch, a fire or lava the volumetric smoke takes
	// its place. Iris does not say which particle is smoke, so it goes by colour and position:
	// grey particles right above a smoking source. Sparks and flames are coloured and stay.
	float particleHigh = max(gammaColor.r, max(gammaColor.g, gammaColor.b));
	float particleLow = min(gammaColor.r, min(gammaColor.g, gammaColor.b));
	if (particleHigh - particleLow < 0.12 * particleHigh + 0.02 && nearSmokeSource(viewToFeet(vViewPos))) discard;
#endif

	vec3 albedo = toLinear(gammaColor);
	vec3 V = -normalize(vViewPos);
#ifdef FW_PARTICLE
	// Particles are small camera-facing cards. Their normal says nothing about their shape.
	vec3 geomNormal = V;
#else
	vec3 geomNormal = normalize(vNormal);
	if (dot(geomNormal, V) < 0.0) geomNormal = -geomNormal;
#endif
	vec3 feet = viewToFeet(vViewPos);
	vec3 worldPos = feet + cameraPosition;
	float dist = length(vViewPos);
	vec3 worldGeom = mat3(gbufferModelViewInverse) * geomNormal;
	vec3 L = normalize(shadowLightPosition);
	vec3 lightColor = readLightColor();

	vec3 N = geomNormal;
	float roughness = 0.45;
	vec3 f0 = vec3(0.04);
	float surfaceClass = 0.0;
	float glassFrostAmount = 0.0;

#ifdef FW_WATER
	bool isWater = vBlockId == ID_WATER;
	if (isWater) {
		surfaceClass = TRANSLUCENT_WATER;
		roughness = 0.035;
		f0 = vec3(0.02);
		if (abs(worldGeom.y) > 0.5) {
			float footprint = max(length(dFdx(worldPos.xz)), length(dFdy(worldPos.xz)));
			vec3 worldNormal = waterNormal(worldPos, dist, footprint);
#if WEATHER_SPLASH_QUALITY > 0
			// Raindrops ring the surface where the rain reaches it.
			if (rainStrength > 0.01 && biome_precipitation == 1 && worldGeom.y > 0.5) {
				vec2 ripple = rainRipples(worldPos.xz, dist) * rainStrength * weatherExposure(feet, vec3(0.0, 1.0, 0.0), vLmCoord.y);
				worldNormal = normalize(worldNormal + vec3(-ripple.x, 0.0, -ripple.y));
			}
#endif
			if (worldGeom.y < 0.0) worldNormal = -worldNormal;
			N = normalize(mat3(gbufferModelView) * worldNormal);
		}
	} else if (vBlockId == ID_ICE) {
		surfaceClass = TRANSLUCENT_ICE;
#ifdef ICE_REFLECTIVITY
		roughness = 0.09;
		f0 = vec3(0.025);
		// Ice is never perfectly flat, which gives its reflections a slow, uneven wobble.
		N = normalize(mat3(gbufferModelView) * perturbWorldNormal(worldGeom, worldPos, 0.012, 0.22));
#else
		roughness = 0.30;
#endif
	} else if (vBlockId == ID_PORTAL) {
		surfaceClass = 0.0;
		roughness = 0.5;
	} else {
		surfaceClass = TRANSLUCENT_GLASS;
		roughness = 0.05;
#ifdef GLASS_WEATHER_EFFECTS
		// Weather on windows open to the sky. In rain, drops sit on the glass and run down it, and
		// bend what is seen through it and in it. In snow, frost grows in from the edges.
		float exposed = weatherExposure(feet, worldGeom, vLmCoord.y) * (1.0 - smoothstep(16.0, 32.0, dist));
		if (rainStrength > 0.01 && exposed > 0.0 && abs(worldGeom.y) < 0.5) {
			vec3 paneAcross = normalize(cross(vec3(0.0, 1.0, 0.0), worldGeom));
			vec2 paneUv = vec2(dot(worldPos, paneAcross), worldPos.y);
			if (biome_precipitation == 2) {
				glassFrostAmount = glassFrost(paneUv, rainStrength * exposed);
			} else if (biome_precipitation == 1) {
				vec2 slope = glassRaindrops(paneUv, frameTimeCounter) * rainStrength * exposed;
				N = normalize(mat3(gbufferModelView) * normalize(worldGeom - paneAcross * slope.x - vec3(0.0, slope.y, 0.0)));
			}
		}
#endif
	}
#endif

	vec3 worldNormal = mat3(gbufferModelViewInverse) * N;
	vec3 visibility = vec3(1.0);
#ifdef FW_PARTICLE
	float NoL = 0.5;
	float facingLight = 1.0;
#else
	float NoL = saturate(dot(N, L));
	float facingLight = dot(geomNormal, L);
#endif
	vec3 specular = vec3(0.0);
#if defined SPECULAR_HIGHLIGHTS && !defined FW_PARTICLE
	if (facingLight > 0.0) specular = specularGGX(N, V, L, roughness, f0) * lightColor;
#endif
#ifndef GLASS_REFLECTIONS
	if (surfaceClass == TRANSLUCENT_GLASS) specular = vec3(0.0);
#endif

	// Water covers large parts of the screen, so the full shadow filter only runs where the sun
	// shows in a highlight. Everywhere else one tap is enough, since only 7% of the surface is lit.
	bool needsShadow = luminance(specular) > 0.002;
#ifdef FW_WATER
	needsShadow = needsShadow || (!isWater && alpha > 0.01);
#else
	needsShadow = true;
#endif
	if (facingLight <= 0.0) {
		visibility = vec3(0.0);
	}
#ifdef HAS_SHADOWS
	else {
		if (needsShadow) {
			float transmitted = 1.0;
			visibility = sampleShadow(feet, worldGeom, cycleNoise(gl_FragCoord.xy, 8, NOISE_STEP_A), transmitted);
		} else {
			visibility = vec3(shadowVisibilityFast(feet + worldGeom * 0.05));
		}
#ifdef HAS_SKYLIGHT
		visibility *= smoothstep(0.0, 0.25, vLmCoord.y);
#endif
	}
#else
	else {
		visibility = vec3(0.0);
	}
#endif

	vec3 lit = albedo * (ambientLighting(worldNormal) + lightColor * visibility * NoL * INV_PI);
	specular *= visibility;

#ifdef FW_WATER
	if (isWater) {
		// The body of the water is shaded in composite2. A faint textured layer keeps
		// the biome colour visible on the surface.
		// Depth fade from the real distance through the water to the block behind it. The surface
		// fades out where it touches a block, so that no highlight can form along that line.
		// The block behind lies on the same pixel ray as this fragment, so the path follows from
		// the two depths alone. That also holds while TAA shifts the image by a fraction of a pixel,
		// which would make a position rebuilt from gl_FragCoord miss by far at flat angles.
		float opaqueDepth = texelFetch(depthtex1, ivec2(gl_FragCoord.xy), 0).r;
		float waterPath = opaqueDepth >= 1.0 ? 64.0 : max(linearDepth(opaqueDepth) + vViewPos.z, 0.0) * dist / max(-vViewPos.z, 1e-3);
		float contactFade = smoothstep(0.0, 0.30, waterPath);
		specular *= contactFade;
		float surfaceAlpha = 0.07 * contactFade;
#ifdef WATER_FOAM
		// Foam gathers in loose, irregular patches where the water is shallow. The pattern must
		// not repeat, because along a straight wall anything periodic turns into a dashed line.
		vec2 foamUv = worldPos.xz * 0.019;
		float foamNoise = texture(noisetex, foamUv + frameTimeCounter * vec2(0.0011, -0.0007)).r * 0.6
			+ texture(noisetex, foamUv * 2.7 - frameTimeCounter * vec2(0.0017, 0.0013)).g * 0.4;
		float foamBand = smoothstep(0.05, 0.30, waterPath) * (1.0 - smoothstep(0.30, 1.40, waterPath));
		float foamPatches = smoothstep(0.54, 0.74, foamNoise);
		float foamFade = 1.0 - smoothstep(8.0, 24.0, dist);
		float foamAlpha = saturate(foamBand * foamPatches * foamFade * step(0.5, worldGeom.y) * 0.14);
		vec3 foamLit = vec3(0.42) * (ambientLighting(worldNormal) + lightColor * visibility * NoL * INV_PI);
		lit = mix(lit, foamLit, foamAlpha / max(foamAlpha + surfaceAlpha, 1e-3));
		surfaceAlpha = saturate(surfaceAlpha + foamAlpha);
#endif
		alpha = surfaceAlpha;
	}

	// Glass filters light by colour. Only its densest pixels, like frames, cover the view.
	vec3 lightFilter = vec3(1.0);
	if (!isWater && vBlockId != ID_PORTAL) {
		vec3 transmission = mix(vec3(1.0), albedo, saturate(alpha * 1.7));
		lightFilter = transmission;
		alpha = smoothstep(0.5, 0.95, alpha) + 0.05 * alpha;
	}
#endif

	outColor = vec4(lit * alpha + specular, alpha);

#if defined FW_WATER && defined GLASS_WEATHER_EFFECTS
	if (glassFrostAmount > 0.0) {
		// Frost is a white, rough layer that covers the glass and scatters light.
		float frostAlpha = saturate(glassFrostAmount * 0.7);
		vec3 frostLit = vec3(0.92, 0.96, 1.0) * (ambientLighting(worldNormal) + lightColor * visibility * max(NoL, 0.3) * INV_PI);
		outColor = vec4(outColor.rgb * (1.0 - frostAlpha) + frostLit * frostAlpha, outColor.a + frostAlpha * (1.0 - outColor.a));
		lightFilter = mix(lightFilter, vec3(1.0), frostAlpha);
	}
#endif

#ifdef FW_WATER
	if (vBlockId == ID_PORTAL) outColor.rgb = albedo * alpha * 3.0;
	outSurface = vec4(encodeNormal(N), packSurface(surfaceClass, vLmCoord.x), vLmCoord.y);
	// Alpha 0 records that water was drawn here, even if glass in front replaces its surface.
	outFilter = vec4(lightFilter, isWater ? 0.0 : 1.0);
#endif

#endif
#endif
#endif
}

#endif
