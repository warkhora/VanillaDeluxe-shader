// VanillaDeluxe - shared uniforms, constants and helpers.
#ifndef VD_COMMON_INCLUDED
#define VD_COMMON_INCLUDED 1

#if DIM_ID == 0
#define HAS_SHADOWS 1
#define HAS_SKYLIGHT 1
#endif
#if DIM_ID == 1
#define HAS_SHADOWS 1
#endif

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;

uniform vec3 cameraPosition;
uniform vec3 cameraPositionFract;
uniform vec3 previousCameraPositionFract;
uniform ivec3 cameraPositionInt;
uniform ivec3 previousCameraPositionInt;
uniform float eyeAltitude;
uniform ivec2 eyeBrightnessSmooth;

uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 shadowLightPosition;
uniform int moonPhase;
uniform float rainStrength;
uniform float wetness;
uniform float thunderStrength;
uniform vec3 fogColor;

uniform float viewWidth;
uniform float viewHeight;
uniform float aspectRatio;
uniform float near;
uniform float far;
uniform float frameTime;
uniform float frameTimeCounter;
uniform int frameCounter;
uniform int isEyeInWater;

uniform float blindness;
uniform float darknessFactor;
uniform float nightVision;

const float PI = 3.14159265359;
const float TAU = 6.28318530718;
const float HALF_PI = 1.57079632679;
const float INV_PI = 0.31830988618;
const float GOLDEN_ANGLE = 2.39996322973;

// Material classes stored in the G-buffer.
const int MAT_NONE = 0;
const int MAT_GENERIC = 1;
const int MAT_FOLIAGE = 2;
const int MAT_HAND = 3;
const int MAT_ENTITY = 4;
const int MAT_CLOUD = 5;
const int MAT_UNLIT = 6;
const int MAT_LAVA = 7;

// Stored lava emission is divided by this, so that its pulsing fits an 8-bit channel.
const float LAVA_EMISSION_RANGE = 1.25;

// Translucent surface classes stored in colortex5.b, with block light in the fraction.
const float TRANSLUCENT_WATER = 1.0;
const float TRANSLUCENT_GLASS = 2.0;
const float TRANSLUCENT_ICE = 3.0;
float packSurface(float surfaceClass, float blockLight) {
	return (surfaceClass + clamp(blockLight, 0.0, 1.0) * 0.9) / 16.0;
}
float unpackSurfaceClass(float v) {
	return floor(v * 16.0 + 0.002);
}
float unpackSurfaceBlockLight(float v) {
	return clamp(fract(v * 16.0 + 0.002) / 0.9, 0.0, 1.0);
}

float saturate(float x) { return clamp(x, 0.0, 1.0); }
vec2 saturate(vec2 x) { return clamp(x, vec2(0.0), vec2(1.0)); }
vec3 saturate(vec3 x) { return clamp(x, vec3(0.0), vec3(1.0)); }
float square(float x) { return x * x; }
float pow5(float x) { float x2 = x * x; return x2 * x2 * x; }
float luminance(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }
vec3 toLinear(vec3 c) { return pow(max(c, vec3(0.0)), vec3(2.2)); }

// ---- Noise ---------------------------------------------------------------
float interleavedNoise(vec2 p) {
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}
float temporalNoise(vec2 p) {
	return interleavedNoise(p + 5.588238 * float(frameCounter % 64));
}
// Noise that repeats after a few frames. Each pixel steps through its values by an irrational
// step, so any run of frames covers them evenly. A temporal filter that spans several such
// cycles then sees the same average in every frame, where a long sequence would leave a slow
// shimmer in the average. Values that together pick one sample use different steps (from the
// R2 and R3 sequences), or they would move in lockstep and cover a line instead of an area.
const float NOISE_STEP_A = 0.61803399;
const float NOISE_STEP_B = 0.75487767;
const float NOISE_STEP_C = 0.56984029;
const float NOISE_STEP_D = 0.81917251;
float cycleNoise(vec2 p, int period, float stepSize) {
	return fract(interleavedNoise(p) + float(frameCounter % period) * stepSize);
}

// ---- Jitter --------------------------------------------------------------
vec2 taaJitter() {
#ifdef TEMPORAL_AA
	vec2 seq = fract(0.5 + float(frameCounter % 64) * vec2(0.7548776662, 0.5698402910)) - 0.5;
	return seq * 2.0 / vec2(viewWidth, viewHeight);
#else
	return vec2(0.0);
#endif
}

// ---- Coordinate spaces ---------------------------------------------------
vec3 viewFromScreen(vec2 uv, float depth) {
	vec4 p = gbufferProjectionInverse * vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
	return p.xyz / p.w;
}
vec3 screenFromView(vec3 v) {
	vec4 c = gbufferProjection * vec4(v, 1.0);
	return c.xyz / c.w * 0.5 + 0.5;
}
vec3 viewToFeet(vec3 v) {
	return mat3(gbufferModelViewInverse) * v + gbufferModelViewInverse[3].xyz;
}
vec3 feetToView(vec3 p) {
	return mat3(gbufferModelView) * p + gbufferModelView[3].xyz;
}
// Positive distance along the view axis for a depth buffer value.
float linearDepth(float depth) {
	return gbufferProjection[3][2] / (depth * 2.0 - 1.0 + gbufferProjection[2][2]);
}
vec3 cameraDelta() {
	return vec3(cameraPositionInt - previousCameraPositionInt) + (cameraPositionFract - previousCameraPositionFract);
}
// Screen position of a point in the previous frame. z holds its previous linear depth.
vec3 reprojectFeet(vec3 feet) {
	vec3 prevFeet = feet + cameraDelta();
	vec3 prevView = mat3(gbufferPreviousModelView) * prevFeet + gbufferPreviousModelView[3].xyz;
	vec4 prevClip = gbufferPreviousProjection * vec4(prevView, 1.0);
	return vec3(prevClip.xy / prevClip.w * 0.5 + 0.5, -prevView.z);
}

// ---- Light directions ----------------------------------------------------
vec3 worldSunDir() { return normalize(mat3(gbufferModelViewInverse) * sunPosition); }
vec3 worldMoonDir() { return normalize(mat3(gbufferModelViewInverse) * moonPosition); }
vec3 worldLightDir() { return normalize(mat3(gbufferModelViewInverse) * shadowLightPosition); }

// ---- Normal encoding -----------------------------------------------------
vec2 encodeNormal(vec3 n) {
	n /= abs(n.x) + abs(n.y) + abs(n.z);
	vec2 e = n.xy;
	if (n.z < 0.0) {
		e = (1.0 - abs(n.yx)) * vec2(n.x >= 0.0 ? 1.0 : -1.0, n.y >= 0.0 ? 1.0 : -1.0);
	}
	return e * 0.5 + 0.5;
}
vec3 decodeNormal(vec2 e) {
	e = e * 2.0 - 1.0;
	vec3 n = vec3(e, 1.0 - abs(e.x) - abs(e.y));
	float t = max(-n.z, 0.0);
	n.x += n.x >= 0.0 ? -t : t;
	n.y += n.y >= 0.0 ? -t : t;
	return normalize(n);
}

// An encoded normal in a single 32-bit float, for history data that is read with texelFetch.
float packNormalFloat(vec2 encoded) {
	return floor(encoded.x * 4095.0 + 0.5) * 4096.0 + floor(encoded.y * 4095.0 + 0.5);
}
vec3 unpackNormalFloat(float packed_) {
	float y = mod(packed_, 4096.0);
	return decodeNormal(vec2((packed_ - y) / 4096.0, y) / 4095.0);
}

// ---- Material id packing (colortex3.b) -----------------------------------
float packMaterial(int materialClass, float parallaxShadow) {
	return float(materialClass * 256 + int(saturate(parallaxShadow) * 255.0 + 0.5)) / 65535.0;
}
int unpackMaterialClass(float v) {
	return int(uint(v * 65535.0 + 0.5) >> 8u);
}
float unpackParallaxShadow(float v) {
	return float(uint(v * 65535.0 + 0.5) & 255u) / 255.0;
}

// ---- Metal colour packing (alpha of the lit scene in colortex0) -----------
// A 16-bit float stores small integers exactly, which leaves room for nine bits of colour.
float packMetalTint(vec3 c) {
	vec3 q = floor(sqrt(saturate(c)) * 7.0 + 0.5);
	return q.r * 64.0 + q.g * 8.0 + q.b;
}
vec3 unpackMetalTint(float v) {
	float i = floor(v + 0.5);
	vec3 q = vec3(floor(i / 64.0), mod(floor(i / 8.0), 8.0), mod(i, 8.0)) / 7.0;
	return q * q;
}

// ---- Emission ------------------------------------------------------------
// Light a surface gives off by itself. Shared by the lighting pass and the bounce light paths,
// so that a glowing block lights its surroundings exactly as brightly as it looks.
vec3 surfaceEmission(vec3 albedo, float emission, int materialClass) {
	if (materialClass == MAT_UNLIT) return albedo * max(emission, 0.5) * 3.2;
	if (emission <= 0.0) return vec3(0.0);
	float emissionScale = 5.0 * float(EMISSION_STRENGTH) / 100.0;
	vec3 emissionColor = albedo;
	if (materialClass == MAT_LAVA) {
		// Very bright light washes out in the tonemapper, so lava is held below that point
		// and given a deeper colour, which keeps it orange in the dark as well.
		emissionScale *= LAVA_EMISSION_RANGE * float(LAVA_EMISSIVE_BRIGHTNESS) * 0.62;
		emissionColor = pow(max(albedo, vec3(0.0)), vec3(1.35));
	}
	return emissionColor * emission * emissionScale;
}

// ---- Wind ----------------------------------------------------------------
vec3 windOffset(vec3 worldPos, float amount) {
	float t = frameTimeCounter;
	float gust = 0.55 + 0.45 * sin(t * 0.37 + worldPos.x * 0.021 + worldPos.z * 0.017);
	float strength = amount * gust * (1.0 + 2.5 * rainStrength);
	vec3 o;
	o.x = sin(t * 1.7 + worldPos.x * 0.8 + worldPos.y * 0.4) + 0.5 * sin(t * 3.1 + worldPos.z * 1.3);
	o.z = sin(t * 1.3 + worldPos.z * 0.9 + worldPos.x * 0.3) + 0.5 * sin(t * 2.7 + worldPos.x * 1.1);
	o.y = 0.3 * sin(t * 2.1 + worldPos.x + worldPos.z);
	return o * strength;
}

#endif
