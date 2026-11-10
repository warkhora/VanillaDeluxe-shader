// VanillaDeluxe - sky LUT. Runs before anything else in the frame so that every
// later program can read the sky colour and the light colours with one fetch.
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

#include "/lib/atmosphere.glsl"
#if DIM_ID == 1
uniform sampler2D noisetex;
#include "/lib/end_sky.glsl"
#endif

/* RENDERTARGETS: 11 */
layout(location = 0) out vec4 outSky;

const vec2 LUT_SIZE = vec2(256.0, 128.0);

vec3 lutDirection(vec2 uv) {
	vec2 st = (uv * LUT_SIZE - 0.5) / (LUT_SIZE - 1.0);
	float azimuth = (st.x - 0.5) * TAU;
	float c = st.y * 2.0 - 1.0;
	float latitude = sign(c) * c * c * HALF_PI;
	float cosLat = cos(latitude);
	return vec3(cosLat * cos(azimuth), sin(latitude), cosLat * sin(azimuth));
}

#if DIM_ID == 0
vec3 skyRadiance(vec3 d, vec3 sunDir, vec3 moonDir, int steps) {
	float scale = float(SKY_BRIGHTNESS) / 100.0;
	return atmApplyWeather(atmSkyRadiance(d, sunDir, moonDir, steps)) * scale;
}

vec3 ambientFromSky(vec3 sunDir, vec3 moonDir, bool upward) {
	vec3 sum = vec3(0.0);
	float total = 0.0;
	if (upward) {
		sum += skyRadiance(vec3(0.0, 1.0, 0.0), sunDir, moonDir, 8);
		total += 1.0;
		for (int i = 0; i < 8; i++) {
			float a = float(i) / 8.0 * TAU;
			vec3 d = normalize(vec3(cos(a), 1.0, sin(a)));
			sum += skyRadiance(d, sunDir, moonDir, 8) * d.y;
			total += d.y;
		}
	} else {
		for (int i = 0; i < 8; i++) {
			float a = float(i) / 8.0 * TAU;
			vec3 d = normalize(vec3(cos(a), 0.35, sin(a)));
			sum += skyRadiance(d, sunDir, moonDir, 8);
			total += 1.0;
		}
	}
	return sum / total;
}
#endif

void main() {
	ivec2 px = ivec2(gl_FragCoord.xy);
	vec3 result = vec3(0.0);
	vec3 dir = lutDirection(texCoord);

#if DIM_ID == 0
	vec3 sunDir = worldSunDir();
	vec3 moonDir = worldMoonDir();
	if (px.y == 0 && px.x <= 2) {
		if (px.x == 2) {
			float sunFade = smoothstep(0.0, 0.06, sunDir.y);
			float moonFade = smoothstep(0.0, 0.06, moonDir.y);
			vec3 sunLight = atmSunIlluminance(sunDir) * sunFade;
			vec3 moonLight = atmMoonIlluminance() * moonFade;
			result = (sunLight + moonLight) * mix(1.0, 0.10, rainStrength) * mix(1.0, 0.45, thunderStrength) * float(SUN_STRENGTH) / 100.0;
		} else {
			// Skylight is scaled up a little so that shaded areas keep their colour. Under the thick
			// clouds of a thunderstorm it dims further, so the land darkens with the sky.
			result = ambientFromSky(sunDir, moonDir, px.x == 0) * 2.3 * mix(1.0, 0.58, thunderStrength) * float(AMBIENT_STRENGTH) / 100.0;
			result += vec3(0.006, 0.008, 0.013);
		}
	} else {
		result = skyRadiance(dir, sunDir, moonDir, 16);
	}
#elif DIM_ID == -1
	// Nether: the biome fog colour is the only light the sky has.
	vec3 fogLinear = toLinear(fogColor);
	if (px.y == 0 && px.x <= 2) {
		if (px.x == 2) {
			result = vec3(0.0);
		} else {
			// A warm neutral light, so that blocks keep their own colours under the biome tint.
			vec3 hue = fogLinear / max(max(fogLinear.r, max(fogLinear.g, fogLinear.b)), 1e-3);
			result = mix(vec3(1.0), hue, 0.35) * 0.17 * float(AMBIENT_STRENGTH) / 100.0;
		}
	} else {
		result = fogLinear * 0.42 + vec3(0.005, 0.0022, 0.0016);
	}
#else
	// The End: a dim violet void with a slow band of nebula light.
	vec3 lightDir = worldLightDir();
	if (px.y == 0 && px.x <= 2) {
		if (px.x == 2) {
			result = vec3(0.62, 0.42, 0.95) * 1.5 * float(SUN_STRENGTH) / 100.0;
		} else {
			result = vec3(0.085, 0.060, 0.130) * float(AMBIENT_STRENGTH) / 100.0;
		}
	} else {
		result = endBaseSky(dir, lightDir) + endAurora(dir, 5);
	}
#endif

	outSky = vec4(max(result, vec3(0.0)), 1.0);
}
#endif
