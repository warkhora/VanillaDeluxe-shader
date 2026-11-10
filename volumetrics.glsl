// VanillaDeluxe - half resolution raymarch of god rays, height fog, cave mist, weather fog,
// Nether fog, smoke and clouds. The result (in-scattered light in rgb, transmittance in a) is
// laid over the scene by composite2 after temporal filtering.
#include "/lib/settings.glsl"
#include "/lib/common.glsl"

#ifdef VSH
out vec2 texCoord;
flat out vec3 vLight;
flat out vec3 vAmbientUp;
flat out vec3 vLightDir;
#include "/lib/sky.glsl"
void main() {
	gl_Position = ftransform();
	texCoord = gl_MultiTexCoord0.xy;
	vLight = readLightColor();
	vAmbientUp = readAmbientUp();
	vLightDir = worldLightDir();
}
#endif

#ifdef FSH
in vec2 texCoord;
flat in vec3 vLight;
flat in vec3 vAmbientUp;
flat in vec3 vLightDir;

uniform sampler2D depthtex0;
uniform sampler2D noisetex;
#ifdef VOLUMETRIC_FOG
uniform int biome_precipitation;
uniform int heldBlockLightValue;
uniform int heldBlockLightValue2;
#endif
#if defined VOLUMETRIC_FOG || defined VOLUMETRIC_SMOKE
// The bloom of the previous frame: a wide blur of the scene, which says how much light there
// is around each point of the screen. Mist and smoke pick up the glow of torches and lava with it.
uniform sampler2D colortex8;
#endif

#include "/lib/sky.glsl"
#include "/lib/shadow.glsl"
#include "/lib/brdf.glsl"
#include "/lib/water.glsl"
#include "/lib/clouds.glsl"
#if defined VOLUMETRIC_SMOKE || defined USE_RT_LIGHT
#include "/lib/rt_light.glsl"
#endif
#ifdef VOLUMETRIC_SMOKE
#include "/lib/smoke.glsl"
#endif
#if DIM_ID == 1 && defined END_CRYSTAL_RAYS
#include "/lib/crystals.glsl"
#endif

/* RENDERTARGETS: 9 */
layout(location = 0) out vec4 outFog;

const float FOG_MAX_DISTANCE = 224.0;

#ifdef VOLUMETRIC_FOG
// Slowly drifting volume noise from two tilted slices of the noise texture.
float fogNoise(vec3 p, float scale, vec2 drift) {
	vec2 uv = p.xz * scale + p.y * scale * vec2(0.37, -0.29) + drift;
	float a = texture(noisetex, uv).r;
	float b = texture(noisetex, uv * 2.03 + vec2(0.31, 0.17) - drift * 0.6).g;
	return a * 0.65 + b * 0.35;
}

// Mist that floats in deep caves. It thickens with depth below the surface and only shows while
// the sky is out of sight, which is how the game knows the player is underground.
float caveFogDensity(vec3 worldPos, float underground) {
	float depthFactor = smoothstep(60.0, 16.0, worldPos.y);
	float wisps = smoothstep(0.30, 0.82, fogNoise(worldPos, 0.045, frameTimeCounter * vec2(0.0035, 0.0025)));
	return float(CAVE_FOG_DENSITY) / 100.0 * 0.040 * underground * depthFactor * (0.25 + 0.75 * wisps);
}

// Banks of fog that roll in over the land with rain, and more so in a thunderstorm.
float weatherFogDensity(vec3 worldPos, float outdoors) {
	float weather = max(rainStrength, thunderStrength * 1.4);
	if (weather <= 0.001) return 0.0;
	float height = exp(-max(worldPos.y - 63.0, 0.0) / 16.0);
	float banks = smoothstep(0.28, 0.80, fogNoise(worldPos, 0.011, frameTimeCounter * vec2(0.010, 0.006)));
	return float(WEATHER_FOG_INTENSITY) / 100.0 * 0.070 * weather * outdoors * height * (0.30 + 0.70 * banks);
}
#endif

// Scattering density of the air at a world height.
float airDensity(float y) {
	float scale = float(FOG_DENSITY) / 100.0;
#if DIM_ID == 0
	float sunHeight = worldSunDir().y;
	float mist = smoothstep(0.32, 0.0, abs(sunHeight)) * 0.0016;
	float base = 0.0010 + mist + rainStrength * 0.010;
	return scale * base * exp(-max(y - 62.0, 0.0) / 48.0);
#elif DIM_ID == 1
	return scale * 0.0065 * exp(-abs(y - 60.0) / 70.0);
#else
	return scale * 0.008;
#endif
}

void main() {
#ifdef VOLUMETRIC_CHECKERBOARD
	// Only half of the pixels are marched in each frame, in a checkerboard that flips every frame.
	// The temporal pass fills in the other half from the frame before. Marks them with alpha -1.
	if (((int(gl_FragCoord.x) + int(gl_FragCoord.y) + frameCounter) & 1) == 1) {
		outFog = vec4(0.0, 0.0, 0.0, -1.0);
		return;
	}
#endif
	ivec2 fullPx = ivec2(gl_FragCoord.xy * 2.0);
	float depth = texelFetch(depthtex0, fullPx, 0).r;
	vec3 feet = viewToFeet(viewFromScreen(texCoord, depth));
	float dist = length(feet);
	vec3 dir = feet / max(dist, 1e-4);
	bool isSky = depth >= 1.0;
	// Repeats every 8 frames, which the temporal filter averages out completely.
	float dither = cycleNoise(gl_FragCoord.xy, 8, NOISE_STEP_A);

	vec3 inScatter = vec3(0.0);
	float transmittance = 1.0;
	float cosTheta = dot(dir, vLightDir);

	float maxDistance = isSky ? FOG_MAX_DISTANCE : min(dist, FOG_MAX_DISTANCE);

	if (isEyeInWater == 1) {
		// ---- Light shafts under water -----------------------------------
		vec3 sigma = waterAbsorption();
		vec3 scatterColor = vec3(0.012, 0.075, 0.085);
		float limit = isSky ? 64.0 : min(dist, 64.0);
#if defined HAS_SHADOWS && defined VOLUMETRIC_LIGHT
		float phase = phaseHG(cosTheta, 0.62) * 2.4 + 0.25;
		float stepSize = limit / float(VL_STEPS);
		for (int i = 0; i < VL_STEPS; i++) {
			float t = (float(i) + dither) * stepSize;
			float vis = shadowVisibilityFast(dir * t);
			inScatter += exp(-sigma * t) * vis * stepSize;
		}
		inScatter *= vLight * scatterColor * phase * 0.20 * float(VL_STRENGTH) / 100.0;
#endif
		transmittance = 1.0;
	}
#if DIM_ID == -1
	else {
#if defined VOLUMETRIC_FOG && NETHER_FOG_DENSITY > 0
		// ---- Nether fog -------------------------------------------------
		// Thick rolling fog in the colour of the biome, glowing orange from the lava sea below.
		vec3 fogTint = toLinear(fogColor);
		vec3 localGlow = texture(colortex8, texCoord).rgb;
		float limit = isSky ? 128.0 : min(dist, 192.0);
		float previous = 0.0;
		for (int i = 0; i < 10; i++) {
			float s = (float(i) + dither) / 10.0;
			float t = limit * s * s;
			float dt = t - previous;
			previous = t;
			vec3 worldPos = cameraPosition + dir * t;
			float billows = fogNoise(worldPos, 0.018, frameTimeCounter * vec2(0.009, -0.006));
			float lavaSea = exp(-max(worldPos.y - 31.0, 0.0) / 22.0);
			float density = float(NETHER_FOG_DENSITY) / 100.0 * 0.020 * (0.35 + 1.1 * billows) * (1.0 + 1.6 * lavaSea) * dt;
			vec3 glow = vec3(1.0, 0.36, 0.08) * 0.45 * lavaSea;
			vec3 lit = fogTint * 1.4 + vec3(0.016, 0.006, 0.004) + glow + localGlow * 0.35;
#if defined USE_RT_LIGHT && defined NETHER_LIGHT_SHAFTS
			// The lights near the camera colour the fog: blue around soul fire, orange around lava.
			// A shadow ray towards the light makes glowstone on the ceiling cast shafts of light.
			// Every other step close to the camera traces a shadow ray, which the temporal filter blends.
			if (i < 6 && (i & 1) == 0 && t < 28.0) {
				vec4 lightNoise = vec4(cycleNoise(gl_FragCoord.xy + float(i) * 13.0, 8, NOISE_STEP_A), cycleNoise(gl_FragCoord.xy + float(i) * 7.0 + 3.0, 8, NOISE_STEP_B),
					cycleNoise(gl_FragCoord.xy + float(i) * 5.0 + 11.0, 8, NOISE_STEP_C), cycleNoise(gl_FragCoord.xy + float(i) * 3.0 + 29.0, 8, NOISE_STEP_D));
				lit += rtBlockLight(dir * t, -dir, true, lightNoise, true) * 0.8;
			}
#endif
			inScatter += transmittance * density * lit;
			transmittance *= exp(-density);
		}
#else
		// ---- Nether haze ------------------------------------------------
		float d = isSky ? 96.0 : min(dist, 256.0);
		float amount = airDensity(cameraPosition.y) * d;
		transmittance = exp(-amount);
		inScatter = skyColorInDirection(dir) * (1.0 - transmittance);
#endif
	}
#else
	else if (isEyeInWater == 0) {
		// ---- Air -------------------------------------------------------
#if (defined HAS_SHADOWS && defined VOLUMETRIC_LIGHT) || defined VOLUMETRIC_FOG
		// A moderate forward lobe. A sharper one floods the whole view when facing a low sun.
		float phase = mix(phaseHG(cosTheta, 0.05), phaseHG(cosTheta, 0.62), 0.40);
		float indoor = float(eyeBrightnessSmooth.y) / 240.0;
		// The ambient value is boosted for surfaces. Air should match the sky behind it instead.
		vec3 ambientScatter = vAmbientUp * 0.42 * mix(0.12, 1.0, indoor * indoor);
		vec3 sunScatter = vLight * phase * float(VL_STRENGTH) / 100.0;
#ifdef VOLUMETRIC_FOG
		// Cave mist is lit by the light around it on the screen, and by the torch the player holds.
		float underground = 1.0 - smoothstep(0.04, 0.45, indoor);
		float outdoors = indoor * indoor;
		vec3 localGlow = texture(colortex8, texCoord).rgb;
		float heldLight = float(max(heldBlockLightValue, heldBlockLightValue2)) / 15.0;
		vec3 caveLight = localGlow * 0.55 + vec3(0.010, 0.011, 0.014) * float(MIN_LIGHT) / 100.0;
		vec3 heldGlow = vec3(1.0, 0.55, 0.25) * 0.35 * heldLight;
		// Falling snow scatters far more light than rain, so snowy weather turns a soft white.
		float snowing = biome_precipitation == 2 ? 1.0 : 0.0;
		vec3 weatherLight = vAmbientUp * mix(0.55, 0.95, snowing) * outdoors + localGlow * mix(0.15, 0.35, snowing);
#endif
		float stepsF = float(VL_STEPS);
		float previous = 0.0;
		for (int i = 0; i < VL_STEPS; i++) {
			float s = (float(i) + dither) / stepsF;
			float t = maxDistance * s * s;
			float dt = t - previous;
			previous = t;
			vec3 p = dir * t;
			float density = airDensity(p.y + cameraPosition.y) * dt;
			float vis = 0.0;
#if defined HAS_SHADOWS && defined VOLUMETRIC_LIGHT
			if (dot(vLight, vLight) > 1e-7) vis = shadowVisibilityFast(p);
#endif
			vec3 light = density * (sunScatter * vis + ambientScatter);
#ifdef VOLUMETRIC_FOG
			vec3 worldPos = p + cameraPosition;
			float cave = caveFogDensity(worldPos, underground) * dt;
			float weather = weatherFogDensity(worldPos, outdoors) * dt;
			light += cave * (caveLight + heldGlow * exp(-t / 7.0));
			light += weather * (weatherLight + sunScatter * vis * 0.5);
			density += cave + weather;
#endif
			inScatter += transmittance * light;
			transmittance *= exp(-density);
		}
		// The stretch past the last step, so the march ends exactly at the surface.
		float rest = max(maxDistance - previous, 0.0);
		float restDensity = airDensity(cameraPosition.y + dir.y * maxDistance) * rest;
		inScatter += transmittance * restDensity * ambientScatter;
		transmittance *= exp(-restDensity);
#else
		float d = maxDistance;
		float amount = airDensity(cameraPosition.y + dir.y * d * 0.5) * d;
		transmittance = exp(-amount);
		inScatter = vAmbientUp * 0.42 * (1.0 - transmittance);
#endif
#if defined VOLUMETRIC_CLOUDS && DIM_ID == 0
		vec4 clouds = marchClouds(cameraPosition, dir, isSky ? 1e7 : dist, dither, vLightDir, vLight, vAmbientUp);
		inScatter += transmittance * clouds.rgb;
		transmittance *= clouds.a;
#endif
	}
#endif

#if DIM_ID == 1 && defined END_CRYSTAL_RAYS
	// ---- Light from the End crystals ------------------------------------
	inScatter += crystalRays(dir, isSky ? 1e4 : dist) * transmittance * 0.35;
#endif

#ifdef VOLUMETRIC_SMOKE
	// ---- Smoke ----------------------------------------------------------
	// Close to the camera, in front of the fog that lies further out.
	if (isEyeInWater == 0) {
		float indoorSmoke = float(eyeBrightnessSmooth.y) / 240.0;
		vec3 smokeAmbient = vAmbientUp * 0.5 * indoorSmoke * indoorSmoke + texture(colortex8, texCoord).rgb * 0.4
			+ vec3(0.010, 0.011, 0.014) * float(MIN_LIGHT) / 100.0;
		// Smoke plumes are thin, so a sample offset that repeats every 8 frames, which the temporal
		// filter averages out completely, keeps them from flickering.
		float smokeDither = cycleNoise(gl_FragCoord.xy + vec2(71.0, 13.0), 8, NOISE_STEP_A);
		vec2 smokeJitter = vec2(cycleNoise(gl_FragCoord.xy + vec2(5.0, 211.0), 8, NOISE_STEP_B), cycleNoise(gl_FragCoord.xy + vec2(149.0, 37.0), 8, NOISE_STEP_C));
		vec4 smoke = marchSmoke(dir, isSky ? 1e4 : dist, smokeAmbient, smokeDither, smokeJitter);
		inScatter = smoke.rgb + smoke.a * inScatter;
		transmittance *= smoke.a;
	}
#endif

	if (any(isnan(inScatter)) || any(isinf(inScatter)) || isnan(transmittance)) {
		inScatter = vec3(0.0);
		transmittance = 1.0;
	}
	outFog = vec4(min(inScatter, vec3(64.0)), saturate(transmittance));
}
#endif
