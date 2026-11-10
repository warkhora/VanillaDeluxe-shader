// VanillaDeluxe - reads the sky LUT written by prepare.fsh.
// Row 0 of the LUT stores per-frame light values:
//   (0,0) ambient for up-facing surfaces, (1,0) ambient for side-facing surfaces
//   (2,0) direct light colour of the current sun or moon
#ifndef VD_SKY_INCLUDED
#define VD_SKY_INCLUDED 1

uniform sampler2D colortex11;

const vec2 SKY_LUT_SIZE = vec2(256.0, 128.0);

vec2 skyDirToUv(vec3 d) {
	float azimuth = atan(d.z, d.x + 1e-6);
	float latitude = asin(clamp(d.y, -1.0, 1.0));
	float v = 0.5 + 0.5 * sign(latitude) * sqrt(abs(latitude) / HALF_PI);
	vec2 uv = vec2(azimuth / TAU + 0.5, v);
	return (uv * (SKY_LUT_SIZE - 1.0) + 0.5) / SKY_LUT_SIZE;
}
vec3 skyColorInDirection(vec3 worldDir) {
	return texture(colortex11, skyDirToUv(worldDir)).rgb;
}
vec3 readAmbientUp() { return texelFetch(colortex11, ivec2(0, 0), 0).rgb; }
vec3 readAmbientSide() { return texelFetch(colortex11, ivec2(1, 0), 0).rgb; }
vec3 readLightColor() { return texelFetch(colortex11, ivec2(2, 0), 0).rgb; }

// Irradiance divided by pi arriving on a surface from the sky.
vec3 skyAmbient(vec3 worldNormal, vec3 up, vec3 side) {
	float t = worldNormal.y;
	vec3 upper = mix(side, up, saturate(t));
	vec3 lower = side * mix(1.0, 0.45, saturate(-t));
	return t >= 0.0 ? upper : lower;
}

// Skylight reaching an interior has bounced off surfaces on its way in, so it falls off
// steeply with the lightmap and loses the blue colour of the open sky.
vec3 applySkyOcclusion(vec3 ambient, float lmSky) {
	float amount = lmSky * lmSky * lmSky;
	vec3 bounced = vec3(luminance(ambient)) * vec3(1.0, 0.95, 0.88);
	return mix(bounced, ambient, smoothstep(0.35, 0.95, lmSky)) * amount;
}

#endif
