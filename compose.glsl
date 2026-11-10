// VanillaDeluxe - lays water, glass, reflections and volumetrics over the lit scene.
#include "/lib/settings.glsl"
#include "/lib/common.glsl"

#ifdef VSH
out vec2 texCoord;
flat out vec3 vLight;
flat out vec3 vAmbientUp;
flat out vec3 vAmbientSide;
#include "/lib/sky.glsl"
void main() {
	gl_Position = ftransform();
	texCoord = gl_MultiTexCoord0.xy;
	vLight = readLightColor();
	vAmbientUp = readAmbientUp();
	vAmbientSide = readAmbientSide();
}
#endif

#ifdef FSH
in vec2 texCoord;
flat in vec3 vLight;
flat in vec3 vAmbientUp;
flat in vec3 vAmbientSide;

uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex3;
uniform sampler2D colortex4;
uniform sampler2D colortex5;
uniform sampler2D colortex12;
uniform sampler2D colortex15;
uniform sampler2D noisetex;

#include "/lib/sky.glsl"
#include "/lib/brdf.glsl"
#include "/lib/water.glsl"
#include "/lib/clouds.glsl"
#include "/lib/ssr.glsl"
#include "/lib/refraction.glsl"

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outColor;

// Sky with a cheap version of the clouds, for reflections that miss the screen.
vec3 environmentColor(vec3 worldDir, float skyLight) {
	vec3 color = skyColorInDirection(worldDir);
#if defined VOLUMETRIC_CLOUDS && DIM_ID == 0
	if (worldDir.y > 0.03) {
		float t = (0.5 * (CLOUD_BASE + CLOUD_TOP) - cameraPosition.y) / worldDir.y;
		if (t > 0.0 && t < CLOUD_MAX_DISTANCE) {
			vec3 p = cameraPosition + worldDir * t;
			float shape = smoothstep(0.0, 0.55, cloudShape(p.xz)) * exp(-t * 0.00042);
			vec3 lit = vAmbientUp * 1.1 + vLight * 0.14;
			color = mix(color, lit, shape);
		}
	}
#endif
#ifdef HAS_SKYLIGHT
	color *= skyLight * skyLight * skyLight;
#endif
	return color;
}

vec3 reflectedLight(vec3 viewPos, vec3 R, float dither, float skyLight, bool traced) {
	vec3 worldR = mat3(gbufferModelViewInverse) * R;
	vec3 fallback = environmentColor(worldR, skyLight);
#ifdef SCREEN_SPACE_REFLECTIONS
	vec2 hitUv;
	if (traced && traceScreenRay(viewPos, R, dither, hitUv)) {
		vec2 edge = min(hitUv, 1.0 - hitUv) * vec2(aspectRatio, 1.0);
		float confidence = saturate(min(edge.x, edge.y) * 9.0);
		return mix(fallback, texture(colortex0, hitUv).rgb, confidence);
	}
#endif
	return fallback;
}

// A microfacet normal for this frame. Accumulated by TAA, it gives a blurred reflection.
vec3 roughReflectionNormal(vec3 N, float roughness, float dither) {
#ifdef ROUGH_REFLECTIONS
	if (roughness > 0.002) {
		float v2 = temporalNoise(gl_FragCoord.xy + vec2(151.0, 43.0));
		float phi = dither * TAU;
		float a = roughness * roughness;
		float cosT = sqrt((1.0 - v2) / max(1.0 + (a - 1.0) * v2, 1e-4));
		float sinT = sqrt(max(1.0 - cosT * cosT, 0.0));
		vec3 up = abs(N.z) < 0.99 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
		vec3 tangentX = normalize(cross(up, N));
		vec3 tangentY = cross(N, tangentX);
		return normalize(tangentX * cos(phi) * sinT + tangentY * sin(phi) * sinT + N * cosT);
	}
#endif
	return N;
}

// Hot air above lava. Looks a short way down the screen for lava that lies in front of this
// pixel, and returns a small, quickly moving offset if it finds any. The noisy tap positions
// are smoothed out by TAA, so four reads per pixel are enough.
#if DIM_ID == -1 && defined NETHER_HEAT_HAZE
// Over the lava seas of the Nether the hot air rises far higher and shimmers more.
const int HAZE_TAPS = 6;
const float HAZE_REACH = 0.30;
const float HAZE_HEIGHT = 7.0;
const float HAZE_AMOUNT = 0.0019;
#else
const int HAZE_TAPS = 4;
const float HAZE_REACH = 0.12;
const float HAZE_HEIGHT = 2.2;
const float HAZE_AMOUNT = 0.0011;
#endif
vec2 lavaHeatOffset(ivec2 px, vec2 uv, float pixelZ) {
	float jitter = cycleNoise(gl_FragCoord.xy + vec2(7.0, 91.0), 8, NOISE_STEP_A);
	float strength = 0.0;
	float nearestLava = 1e5;
	for (int i = 0; i < HAZE_TAPS; i++) {
		float s = (float(i) + jitter) / float(HAZE_TAPS);
		float rise = s * s * HAZE_REACH + 0.002;
		int y = px.y - int(rise * viewHeight);
		if (y < 0) break;
		ivec2 p = ivec2(px.x, y);
		if (unpackMaterialClass(texelFetch(colortex3, p, 0).b) != MAT_LAVA) continue;
		// colortex3 is not cleared, so sky pixels can hold old values.
		float d = texelFetch(depthtex1, p, 0).r;
		if (d >= 1.0) continue;
		float lavaZ = linearDepth(d);
		if (lavaZ > pixelZ + 1.0) continue;
		float blocksAbove = rise * 2.0 * lavaZ / gbufferProjection[1][1];
		strength = max(strength, 1.0 - smoothstep(0.5, HAZE_HEIGHT, blocksAbove));
		nearestLava = min(nearestLava, lavaZ);
	}
	if (strength <= 0.0) return vec2(0.0);
	float t = frameTimeCounter;
	float amount = HAZE_AMOUNT * strength / (1.0 + nearestLava * 0.05);
	float waveX = sin(uv.y * 125.0 + t * 7.0) + 0.5 * sin(uv.y * 270.0 - t * 11.0 + uv.x * 40.0);
	float waveY = sin(uv.y * 90.0 - t * 5.0 + uv.x * 60.0);
	return vec2(waveX, waveY * 0.5) * amount;
}

// Depth-aware upsampling of the half resolution volumetrics.
vec4 readVolumetrics(float linearZ, float depth) {
	vec2 halfPos = gl_FragCoord.xy * 0.5 - 0.5;
	ivec2 base = ivec2(floor(halfPos));
	vec2 f = halfPos - vec2(base);
	vec4 sum = vec4(0.0);
	float total = 0.0;
	ivec2 bounds = ivec2(viewWidth, viewHeight) / 2 - 1;
	for (int y = 0; y <= 1; y++) {
		for (int x = 0; x <= 1; x++) {
			ivec2 p = clamp(base + ivec2(x, y), ivec2(0), bounds);
			float sampleDepth = texelFetch(depthtex0, p * 2, 0).r;
			float bilinear = (x == 0 ? 1.0 - f.x : f.x) * (y == 0 ? 1.0 - f.y : f.y);
			float weight;
			if (depth >= 1.0) {
				weight = sampleDepth >= 1.0 ? 1.0 : 0.02;
			} else {
				float z = sampleDepth >= 1.0 ? 1e5 : linearDepth(sampleDepth);
				weight = exp(-abs(z - linearZ) / (0.03 * linearZ + 0.1));
			}
			float w = bilinear * weight + 1e-4;
			sum += texelFetch(colortex12, p, 0) * w;
			total += w;
		}
	}
	return sum / total;
}

void main() {
	ivec2 px = ivec2(gl_FragCoord.xy);
	vec2 uv = texCoord;
	float depth0 = texelFetch(depthtex0, px, 0).r;
	float depth1 = texelFetch(depthtex1, px, 0).r;
	vec3 scene = texelFetch(colortex0, px, 0).rgb;
	vec4 translucent = texelFetch(colortex4, px, 0);
	vec4 surface = texelFetch(colortex5, px, 0);
	float surfaceClass = unpackSurfaceClass(surface.b);

	vec3 viewPos0 = viewFromScreen(uv, depth0);
	vec3 feet0 = viewToFeet(viewPos0);
	float dist0 = length(viewPos0);
	vec3 V = normalize(-viewPos0);
	vec3 worldDir = normalize(feet0);
	float linearZ0 = depth0 >= 1.0 ? 1e5 : linearDepth(depth0);
	float dither = temporalNoise(gl_FragCoord.xy + vec2(29.0, 53.0));

	if (isEyeInWater != 2) {
		vec2 heatOffset = lavaHeatOffset(px, uv, linearZ0);
		if ((heatOffset.x != 0.0 || heatOffset.y != 0.0) && unpackMaterialClass(texelFetch(colortex3, px, 0).b) != MAT_HAND) {
			scene = texture(colortex0, uv + heatOffset).rgb;
		}
	}

	if (surfaceClass > 0.5) {
		// ---- Water, glass and ice ----------------------------------------
		vec3 N = decodeNormal(surface.rg);
		if (dot(N, V) < 0.0) N = -N;
		float NoV = saturate(dot(N, V));
		float skyLight = surface.a;
		bool isWater = surfaceClass < 1.5;
		bool isIce = surfaceClass > 2.5;
		vec4 lightFilter = texelFetch(colortex15, px, 0);
		bool cameraInWater = isEyeInWater == 1;

		vec3 viewPos1 = viewFromScreen(uv, depth1);
		float waterPath = depth1 >= 1.0 ? 64.0 : max(distance(viewPos0, viewPos1), 0.0);
		// Depth fade: where water meets a block, the surface fades out over a few centimetres.
		// Reflections are strongest at flat angles, and would otherwise draw a bright line there.
		float contactFade = smoothstep(0.0, 0.30, waterPath);

		vec3 background = scene;
#ifdef WATER_REFRACTION
		if (isWater) {
			// Only the waves bend the view. The normal of a flat surface depends on the camera
			// angle, so using it directly would shift the whole image under the water.
			vec3 up = mat3(gbufferModelView) * vec3(0.0, 1.0, 0.0);
			float facing = dot(N, up);
			vec2 ripple = abs(facing) > 0.7 ? (N - up * sign(facing)).xy : vec2(0.0);
			float strength = saturate(waterPath * 0.35) * 0.22;
			vec2 offset = ripple * strength / max(1.0, linearZ0 * 0.12);
			offset.x /= aspectRatio;
			// No bending at the edge of the screen, where the sample would have to be clamped.
			vec2 edgeDistance = min(uv, 1.0 - uv);
			offset *= saturate(min(edgeDistance.x, edgeDistance.y) * 12.0);
			vec2 refractedUv = saturate(uv - offset);
			float refractedDepth = texture(depthtex1, refractedUv).r;
			// Reject samples that lie in front of the surface, or the view would bend through them.
			if (refractedDepth > depth0) {
				background = texture(colortex0, refractedUv).rgb;
				if (refractedDepth < 1.0) {
					waterPath = max(distance(viewPos0, viewFromScreen(refractedUv, refractedDepth)), 0.0);
				} else {
					waterPath = 64.0;
				}
			}
		}
		if (!isWater) {
			// Ice and glass bend the ray itself, so a flat surface shifts the image only as much
			// as it physically would. Near the screen edge the refracted image fades to the
			// straight one, which keeps the two from shearing against each other.
			float behind = depth1 >= 1.0 ? 64.0 : waterPath;
			vec2 bentUv = isIce
				? refractThroughSolid(viewPos0, N, V, 1.31, min(behind, 4.0), uv)
				: refractThroughPane(viewPos0, N, V, 1.5, 0.12, behind, uv);
			vec2 edgeDistance = min(bentUv, 1.0 - bentUv);
			float onScreen = saturate(min(edgeDistance.x, edgeDistance.y) * 24.0);
			if (onScreen > 0.0 && texture(depthtex1, bentUv).r > depth0) {
				background = mix(background, texture(colortex0, bentUv).rgb, onScreen);
			}
		}
#endif
		if (isIce) {
			// Light picks up a cold blue on its way through the body of the ice.
			background *= exp(-vec3(0.13, 0.045, 0.018) * min(waterPath, 8.0));
		}
		// Water behind glass keeps its colour, although glass replaced its surface data here.
		if ((isWater || lightFilter.a < 0.5) && !isIce && !cameraInWater) {
			// The water only scatters light that really reaches it: the sky where it is open to the
			// sky, and the block light at its surface. With neither, it stays completely dark.
			float blockLight = unpackSurfaceBlockLight(surface.b);
			vec3 volumeAmbient = vAmbientUp * skyLight * skyLight;
			volumeAmbient += vec3(1.0, 0.60, 0.28) * blockLight * blockLight * blockLight * float(BLOCKLIGHT_STRENGTH) / 100.0;
			background = waterVolume(background, waterPath, volumeAmbient, vLight * saturate(worldLightDir().y) * skyLight);
#if DIM_ID == 0
			// Moonlight on pale sand under water would read as a glow, because the eye has adapted
			// to the dark land around it. Only block light keeps its full strength at night.
			float moonlit = 1.0 - smoothstep(-0.06, 0.10, worldSunDir().y);
			background *= mix(1.0, mix(0.42, 1.0, saturate(blockLight * 2.0)), moonlit);
#endif
		}

		background *= lightFilter.rgb;

		// ---- Fresnel ---------------------------------------------------
		float reflectance;
		if (isWater && cameraInWater) {
			// Seen from below, most of the surface mirrors the water back.
			float sinT2 = 1.7689 * (1.0 - NoV * NoV);
			if (sinT2 >= 1.0) {
				reflectance = 1.0;
			} else {
				float cosT = sqrt(1.0 - sinT2);
				reflectance = fresnelDielectric(cosT, 0.02);
			}
		} else if (isWater) {
			reflectance = fresnelDielectric(NoV, 0.02) * contactFade;
		} else if (isIce) {
			reflectance = fresnelDielectric(NoV, 0.025);
		} else {
			// A pane reflects from both of its surfaces.
			float single = fresnelDielectric(NoV, 0.04);
			reflectance = 2.0 * single / (1.0 + single);
#ifndef GLASS_REFLECTIONS
			reflectance = 0.0;
#endif
		}

		vec3 reflectionNormal = N;
		bool traced = true;
		if (isIce) {
#ifdef ICE_REFLECTIVITY
			reflectionNormal = roughReflectionNormal(N, 0.09, dither);
#else
			traced = false;
#endif
		}
		vec3 R = reflect(-V, reflectionNormal);
		vec3 reflection = vec3(0.0);
		// Water reflects at flat angles, where a ray with fully random steps can hit a thin object in
		// one pixel and miss it in the next, which leaves rows of dots. A little jitter is enough to
		// hide the steps of the ray, without letting neighbouring pixels disagree like that.
		float reflectionDither = isWater ? 0.5 + (dither - 0.5) * 0.3 : dither;
		if (reflectance > 0.0) reflection = reflectedLight(viewPos0 + N * 0.02, R, reflectionDither, cameraInWater ? 0.0 : skyLight, traced);
		if (cameraInWater && isWater) reflection =mix(reflection, vec3(0.012, 0.06, 0.07) * (vAmbientUp + vLight * 0.1), 0.5);

		scene = background * (1.0 - reflectance) + reflection * reflectance;
	}
#if defined SCREEN_SPACE_REFLECTIONS && defined SSR_ON_SURFACES
	else if (depth1 < 1.0) {
		// ---- Polished and wet opaque surfaces ----------------------------
		vec4 material = texelFetch(colortex2, px, 0);
		vec4 geometry = texelFetch(colortex3, px, 0);
		int materialClass = unpackMaterialClass(geometry.b);
		float smoothness = material.r;
		vec3 f0;
		float metalness;
		decodeReflectance(material.g, vec3(0.0), f0, metalness);
		if ((smoothness >= 0.45 || metalness > 0.5) && materialClass != MAT_HAND && materialClass != MAT_UNLIT) {
			vec4 normalLight = texelFetch(colortex1, px, 0);
			vec3 N = decodeNormal(normalLight.rg);
			float roughness = (1.0 - smoothness) * (1.0 - smoothness);
			if (metalness > 0.5) f0 = unpackMetalTint(texelFetch(colortex0, px, 0).a);
			vec3 sampleNormal = roughReflectionNormal(N, roughness, dither);
			vec3 R = reflect(-V, sampleNormal);
			float NoV = saturate(dot(sampleNormal, V));
			vec3 F = f0 + (max(vec3(1.0 - roughness), f0) - f0) * pow5(1.0 - NoV);
			vec3 Ng = decodeNormal(geometry.rg);
			if (dot(R, Ng) > 0.0) {
				float occlusion = geometry.a;
				vec3 reflection = reflectedLight(viewPos0 + Ng * (0.01 + dist0 * 0.002), R, dither, normalLight.a, true) * occlusion;
				scene += F * reflection * mix(1.0, 0.65, roughness);
			}
		}
	}
#endif

	// ---- Translucent colour, premultiplied ------------------------------
	scene = scene * (1.0 - translucent.a) + translucent.rgb;

	// ---- Air, cloud and water between the camera and the scene ----------
	vec4 fog = readVolumetrics(linearZ0, depth0);
	if (isEyeInWater == 1) {
		float d = depth0 >= 1.0 ? 96.0 : dist0;
		// Skylight at the eye falls with depth, so deep water gets darker and darker.
		float eyeSky = float(eyeBrightnessSmooth.y) / 240.0;
		float depthLight = mix(0.10, 1.0, eyeSky * eyeSky);
		vec3 ambient = vAmbientUp * 0.8 * depthLight;
		scene = waterVolume(scene, d, ambient, vLight * saturate(worldLightDir().y) * depthLight);
		scene += fog.rgb * depthLight;
	} else if (isEyeInWater == 2) {
		float amount = 1.0 - exp(-dist0 * 1.1);
		scene = mix(scene, vec3(4.5, 1.1, 0.12), amount);
	} else if (isEyeInWater == 3) {
		float amount = 1.0 - exp(-dist0 * 0.9);
		scene = mix(scene, vec3(0.75, 0.82, 0.90) * (vAmbientUp + vec3(0.25)), amount);
	} else {
#if DIM_ID == 0
		// Long distance haze and the fade to the sky at the edge of the render distance. The haze
		// takes the colour of the sky only where the sky actually reaches. The sky is brightest
		// and reddest at the horizon, so in a cave it would otherwise lay a reddish line across
		// every wall at eye height, in the middle of the screen when looking straight ahead.
		if (depth0 < 1.0) {
			float aerial = 1.0 - exp(-dist0 * (0.00026 + rainStrength * 0.0018 + thunderStrength * 0.0016) * float(FOG_DENSITY) / 100.0);
			float border = smoothstep(far * 0.72, far * 0.99, length(feet0.xz));
			float amount = saturate(aerial + border - aerial * border);
			float hazeSky = surfaceClass > 0.5 ? surface.a : texelFetch(colortex1, px, 0).a;
			scene = mix(scene, skyColorInDirection(worldDir) * hazeSky * hazeSky, amount);
		}
#elif DIM_ID == 1
		if (depth0 < 1.0) {
			float border = smoothstep(far * 0.7, far * 0.99, length(feet0.xz));
			scene = mix(scene, skyColorInDirection(worldDir), border);
		}
#else
		if (depth0 < 1.0) {
			float border = smoothstep(far * 0.45, far * 0.95, length(feet0.xz));
			scene = mix(scene, skyColorInDirection(worldDir), border);
		}
#endif
		scene = scene * fog.a + fog.rgb;
	}

	// ---- Status effects -------------------------------------------------
	if (blindness > 0.001) {
		scene *= mix(1.0, exp(-dist0 * 0.55), blindness);
	}
	if (darknessFactor > 0.001) {
		scene *= mix(1.0, exp(-dist0 * 0.16), darknessFactor);
	}

	if (any(isnan(scene)) || any(isinf(scene))) scene = vec3(0.0);
	outColor = vec4(clamp(scene, vec3(0.0), vec3(400.0)), 1.0);
}
#endif
