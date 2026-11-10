// VanillaDeluxe - final image: depth of field, rain, snow and splashes, bloom, lens flare and
// dirt, tonemapping and colour grading.
#include "/lib/settings.glsl"
#include "/lib/common.glsl"
#include "/lib/tonemap.glsl"

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
uniform sampler2D colortex8;
uniform sampler2D colortex13;
#ifdef RAIN_REFRACTION
// Offsets from the raindrops of this frame, written by gbuffers_weather.
uniform sampler2D colortex16;
#endif
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D colortex1;
uniform sampler2D colortex3;
uniform sampler2D noisetex;
uniform int biome_precipitation;
#include "/lib/sky.glsl"
#include "/lib/brdf.glsl"
#include "/lib/weather.glsl"
#include "/lib/weather_map.glsl"
#include "/lib/precip.glsl"
#ifdef USE_RT_LIGHT
#include "/lib/rt_light.glsl"
#endif

layout(location = 0) out vec4 outFinal;

vec3 sharpen(vec3 center, ivec2 px) {
#ifdef TEMPORAL_AA
#if TAA_SHARPEN > 0
	ivec2 maxPx = ivec2(viewWidth, viewHeight) - 1;
	vec3 north = texelFetch(colortex7, clamp(px + ivec2(0, 1), ivec2(0), maxPx), 0).rgb;
	vec3 south = texelFetch(colortex7, clamp(px - ivec2(0, 1), ivec2(0), maxPx), 0).rgb;
	vec3 east = texelFetch(colortex7, clamp(px + ivec2(1, 0), ivec2(0), maxPx), 0).rgb;
	vec3 west = texelFetch(colortex7, clamp(px - ivec2(1, 0), ivec2(0), maxPx), 0).rgb;

	// Contrast adaptive sharpening, working on compressed brightness to avoid halos.
	float c = luminance(center);
	float n = luminance(north);
	float s = luminance(south);
	float e = luminance(east);
	float w = luminance(west);
	float low = min(c, min(n, min(s, min(e, w))));
	float high = max(c, max(n, max(s, max(e, w))));
	float amount = sqrt(saturate(min(low, 1.0 - min(high, 1.0)) / max(high, 1e-4)));
	float weight = amount * -0.125 * float(TAA_SHARPEN) / 100.0 * 1.6;
	vec3 result = (center + (north + south + east + west) * weight) / (1.0 + 4.0 * weight);
	return max(result, vec3(0.0));
#else
	return center;
#endif
#else
	return center;
#endif
}

#ifdef DEPTH_OF_FIELD
// Size of the blur at a linear depth, in pixels: zero at the focus distance, growing in front of
// it and behind it the way a camera lens blurs.
float circleOfConfusion(float z, float focus, float scale) {
	return min(abs(1.0 - focus / max(z, 0.05)) * 7.0, 11.0) * scale;
}

// Depth of field by gathering: every nearby pixel whose own blur reaches this one adds to it.
// Objects behind a pixel only count as far as that pixel is blurred itself, so a sharp object in
// focus does not take on the blur of the background. The hand stays sharp.
vec3 depthOfField(vec3 sharp, ivec2 px) {
	float focus = texelFetch(colortex13, ivec2(0), 0).b;
	if (!(focus > 0.0)) return sharp;
	float depth = texelFetch(depthtex0, px, 0).r;
	if (depth < 1.0 && unpackMaterialClass(texelFetch(colortex3, px, 0).b) == MAT_HAND) return sharp;
	float scale = viewHeight / 1440.0 * float(DOF_STRENGTH) / 100.0;
	float z = depth >= 1.0 ? 1e4 : linearDepth(depth);
	float centerBlur = circleOfConfusion(z, focus, scale);
	if (centerBlur < 0.6) return sharp;
	vec2 size = vec2(viewWidth, viewHeight);
	vec3 sum = sharp;
	float total = 1.0;
	float angle = interleavedNoise(gl_FragCoord.xy) * TAU;
	// More taps for a wider blur. A slight blur needs few, and most of a distant landscape is slight.
	int taps = int(clamp(centerBlur * 2.2, 6.0, 24.0));
	for (int i = 0; i < taps; i++) {
		float r = sqrt((float(i) + 0.5) / float(taps)) * centerBlur;
		float a = angle + float(i) * GOLDEN_ANGLE;
		vec2 uv = (vec2(px) + 0.5 + vec2(cos(a), sin(a)) * r) / size;
		float sampleDepth = texture(depthtex0, uv).r;
		float sampleZ = sampleDepth >= 1.0 ? 1e4 : linearDepth(sampleDepth);
		// The hand is drawn much closer than anything in the world. It never blurs into the scene.
		if (sampleZ < 0.6) continue;
		float sampleBlur = circleOfConfusion(sampleZ, focus, scale);
		float reach = sampleZ > z ? min(sampleBlur, centerBlur) : sampleBlur;
		float w = saturate(reach - r + 1.0);
		sum += texture(colortex7, uv).rgb * w;
		total += w;
	}
	return sum / total;
}
#endif

#ifdef TILT_SHIFT
// Tilt-shift: the lens is tilted, so only a horizontal band across the middle is in focus. The
// blur grows smoothly towards the top and the bottom, which makes the world look like a model.
vec3 tiltShift(vec3 sharp, ivec2 px) {
	float band = float(TILT_SHIFT_BAND) / 100.0 * 0.5;
	float away = abs((float(px.y) + 0.5) / viewHeight - 0.5);
	float blur = smoothstep(band, band + 0.32, away) * 9.0 * viewHeight / 1440.0 * float(TILT_SHIFT_STRENGTH) / 100.0;
	if (blur < 0.5) return sharp;
	vec2 size = vec2(viewWidth, viewHeight);
	vec3 sum = sharp;
	float total = 1.0;
	float angle = interleavedNoise(gl_FragCoord.xy) * TAU;
	int taps = int(clamp(blur * 2.2, 6.0, 20.0));
	for (int i = 0; i < taps; i++) {
		float r = sqrt((float(i) + 0.5) / float(taps)) * blur;
		float a = angle + float(i) * GOLDEN_ANGLE;
		vec2 uv = (vec2(px) + 0.5 + vec2(cos(a), sin(a)) * r) / size;
		sum += texture(colortex7, uv).rgb;
		total += 1.0;
	}
	return sum / total;
}
#endif

#ifdef LENS_FLARE
// Flare from the sun or the moon: ghosts of the aperture along the line through the middle of the
// screen, a faint halo and a starburst. Scaled by how much of the light is actually seen, which
// clouds and terrain in front of it reduce.
vec3 lensFlare(vec2 uv, out float seen) {
	seen = 0.0;
	vec4 clip = gbufferProjection * vec4(shadowLightPosition, 1.0);
	if (clip.w <= 0.0) return vec3(0.0);
	vec2 lightUv = clip.xy / clip.w * 0.5 + 0.5;
	if (any(lessThan(lightUv, vec2(-0.1))) || any(greaterThan(lightUv, vec2(1.1)))) return vec3(0.0);
	vec3 lightColor = readLightColor();
	// Measured once per frame by the exposure pass.
	seen = texelFetch(colortex13, ivec2(0), 0).a;
	if (seen <= 0.001) return vec3(0.0);

	vec2 aspect = vec2(aspectRatio, 1.0);
	vec2 toCenter = vec2(0.5) - lightUv;
	vec3 flare = vec3(0.0);
	const float positions[5] = float[5](0.45, 0.75, 1.15, 1.45, 1.85);
	const float radii[5] = float[5](0.035, 0.018, 0.075, 0.025, 0.12);
	const vec3 tints[5] = vec3[5](vec3(0.9, 0.5, 0.25), vec3(0.4, 0.8, 0.5), vec3(0.35, 0.45, 1.0), vec3(1.0, 0.75, 0.4), vec3(0.6, 0.4, 0.9));
	for (int i = 0; i < 5; i++) {
		vec2 ghost = lightUv + toCenter * positions[i];
		float d = length((uv - ghost) * aspect);
		float disc = smoothstep(radii[i], radii[i] * 0.6, d);
		// The largest ghost is a ring, as from the edge of the aperture.
		if (i == 4) disc = exp(-pow((d - radii[i]) * 60.0, 2.0)) * 0.6;
		flare += tints[i] * disc * 0.10;
	}
	float d = length((uv - lightUv) * aspect);
	float angle = atan(uv.y - lightUv.y, (uv.x - lightUv.x) * aspectRatio);
	float star = pow(abs(cos(angle * 3.0)), 60.0) + pow(abs(cos(angle * 3.0 + 0.5236)), 90.0) * 0.6;
	flare += vec3(1.0, 0.92, 0.80) * star * exp(-d * 9.0) * 0.25;
	flare += vec3(0.75, 0.85, 1.0) * exp(-pow((d - 0.32) * 18.0, 2.0)) * 0.035;
	return flare * lightColor * seen * float(LENS_FLARE_STRENGTH) / 100.0 * 0.22;
}
#endif

#ifdef LENS_DIRT
// Smudges and dust on the lens. They only show where a bright light shines through them.
float lensDirt(vec2 uv) {
	vec2 p = uv * vec2(aspectRatio, 1.0);
	float smudges = smoothstep(0.55, 0.95, texture(noisetex, p * 0.31).r) * 0.8;
	float specks = smoothstep(0.80, 0.98, texture(noisetex, p * 1.7 + 0.37).g) * 0.6;
	float film = 0.04 + 0.04 * texture(noisetex, p * 0.09 + 0.71).b;
	return smudges + specks + film;
}
#endif

void main() {
	ivec2 px = ivec2(gl_FragCoord.xy);
	vec3 color = texelFetch(colortex7, px, 0).rgb;
	color = sharpen(color, px);
#ifdef DEPTH_OF_FIELD
	color = depthOfField(color, px);
#endif
#ifdef TILT_SHIFT
	color = tiltShift(color, px);
#endif
#ifdef RAIN_REFRACTION
	// Each falling drop bends the finished image behind it. Done here, after temporal filtering,
	// so the streaks stay crisp instead of smearing as they move.
	vec4 rainBend = texelFetch(colortex16, px, 0);
	if (rainBend.z > 0.01) {
		vec2 bentUv = clamp(texCoord + rainBend.xy, vec2(0.0), vec2(1.0));
		color = mix(color, texture(colortex7, bentUv).rgb, saturate(rainBend.z * 1.6));
	}
#endif

	vec2 fromCenter = texCoord - 0.5;

#ifdef CHROMATIC_ABERRATION
	// Lens fringing grows with the square of the distance from the centre.
	float fringe = dot(fromCenter, fromCenter) * 0.0052 * float(CA_STRENGTH) / 100.0;
	if (fringe > 0.00012) {
		color.r = texture(colortex7, texCoord + fromCenter * fringe).r;
		color.b = texture(colortex7, texCoord - fromCenter * fringe).b;
	}
#endif

#if defined USE_PRECIPITATION && DIM_ID == 0
	// ---- Rain, snow and splashes, drawn crisp after temporal filtering ------------------
	if (rainStrength > 0.01 && isEyeInWater == 0) {
		float depth0 = texelFetch(depthtex0, px, 0).r;
		vec3 viewPos = viewFromScreen(texCoord, depth0);
		vec3 feet = viewToFeet(viewPos);
		float sceneDist = depth0 >= 1.0 ? 1e4 : length(viewPos);
		vec3 dir = normalize(mat3(gbufferModelViewInverse) * viewFromScreen(texCoord, 1.0));
		float pixelAngle = 2.0 / (gbufferProjection[1][1] * viewHeight);
		vec3 localGlow = texture(colortex8, texCoord).rgb;
		float towardsLight = dot(dir, worldLightDir());
		vec4 lightNoise = vec4(cycleNoise(gl_FragCoord.xy, 8, NOISE_STEP_A), cycleNoise(gl_FragCoord.xy + 3.0, 8, NOISE_STEP_B),
			cycleNoise(gl_FragCoord.xy + 7.0, 8, NOISE_STEP_C), cycleNoise(gl_FragCoord.xy + 11.0, 8, NOISE_STEP_D));
		if (biome_precipitation == 2) {
			vec3 flakeFeet;
			float flakes = snowField(dir, sceneDist, 0.0, pixelAngle, rainStrength, flakeFeet).a;
			if (flakes > 0.0) {
				// White flakes in the light of the sky, the sun or moon behind them, and the glow of
				// the scene around them, which is where torches and lava light them up.
				vec3 flakeLight = readAmbientUp() * 1.05 + readLightColor() * (0.10 + 0.30 * phaseHG(towardsLight, 0.45)) + localGlow * 0.8;
#ifdef USE_RT_LIGHT
				flakeLight += rtBlockLight(flakeFeet, -dir, true, lightNoise, false) * 1.3;
#endif
				color = mix(color, flakeLight, flakes * 0.9);
			}
		} else if (biome_precipitation == 1) {
#ifdef GROUND_SPLASH_PARTICLES
			if (depth0 < 1.0 && texelFetch(depthtex1, px, 0).r == depth0) {
				vec4 geometry = texelFetch(colortex3, px, 0);
				vec3 groundNormal = mat3(gbufferModelViewInverse) * decodeNormal(geometry.rg);
				float groundSky = texelFetch(colortex1, px, 0).a;
				if (groundNormal.y > 0.7 && unpackMaterialClass(geometry.b) != MAT_HAND) {
					// Only where the rain actually lands: never under a roof.
					float reach = weatherExposure(feet, groundNormal, groundSky);
					if (reach > 0.0) {
						float droplets = splashField(dir, feet, sceneDist, pixelAngle, rainStrength * (1.0 + 0.5 * thunderStrength)) * reach;
						if (droplets > 0.0) {
							vec3 splashLight = readAmbientUp() * 0.9 + readLightColor() * (0.05 + 0.4 * phaseHG(towardsLight, 0.7)) + localGlow;
							color = mix(color, splashLight, droplets * 0.75);
						}
					}
				}
			}
#endif
		}
	}
#endif

#ifdef BLOOM
	vec3 bloom = texture(colortex8, texCoord).rgb;
	float bloomAmount = 0.075 * float(BLOOM_STRENGTH) / 100.0;
	if (isEyeInWater == 1) bloomAmount *= 2.2;
	bloomAmount *= 1.0 + rainStrength * 0.8;
	color = mix(color, bloom, saturate(bloomAmount));
#endif

	float lightSeen = 0.0;
#ifdef LENS_FLARE
	color += lensFlare(texCoord, lightSeen);
#endif
#ifdef LENS_DIRT
	// Only light that is bright for the eye at its current exposure lights up the dirt: lamps and
	// lava at night, the sun by day. Dim glow, however much of it there is, leaves the lens clear.
	float dirtExposure = max(texelFetch(colortex13, ivec2(0), 0).r * texelFetch(colortex13, ivec2(0), 0).g, 1e-3);
	vec3 glare = max(texture(colortex8, texCoord).rgb * dirtExposure - 0.7, vec3(0.0)) / dirtExposure;
	// The sun lights the dirt most strongly close to where it is in the image.
	vec3 dirtLight = glare * 0.5 + readLightColor() * lightSeen * 0.0025;
	if (max(dirtLight.r, max(dirtLight.g, dirtLight.b)) > 1e-5) color += dirtLight * lensDirt(texCoord) * float(LENS_DIRT_STRENGTH) / 100.0;
#endif

	// The eye sees almost no colour in dim light, so moonlit scenes drift to a cool grey.
	// Anything lit by a torch or lamp is far brighter and keeps its colour.
	float sceneLuminance = luminance(color);
	float scotopic = 1.0 - smoothstep(0.002, 0.038, sceneLuminance);
	color = mix(color, sceneLuminance * vec3(0.78, 0.88, 1.18), scotopic * 0.66);

	vec2 exposureData = texelFetch(colortex13, ivec2(0), 0).rg;
	color *= exposureData.r * exposureData.g;

#ifdef VIGNETTE
	float vignette = 1.0 - dot(fromCenter, fromCenter) * 0.55;
	color *= vignette * vignette;
#endif

	color = applyTonemap(color);
	color = applyGrade(color);
	color = linearToSrgb(color);

	// One step of dither removes banding in dark gradients and the sky.
	float dither = interleavedNoise(gl_FragCoord.xy + float(frameCounter % 16) * 7.0);
	color += (dither - 0.5) / 255.0;

	outFinal = vec4(color, 1.0);
}
#endif
