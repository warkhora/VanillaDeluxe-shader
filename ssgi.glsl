// VanillaDeluxe - ray traced bounce light. One path per half resolution pixel and frame runs
// through the depth buffer for up to RT_BOUNCES bounces. Every surface a path hits is lit right
// there: by its own glow, by the sun through the shadow map, by the sky and by the ray traced
// block light. It reflects that light in its own colour and passes the rest on to the next
// bounce, so a red wall casts red light, which a white floor then reflects further. Weak paths
// end early (Russian roulette), which keeps long paths affordable without darkening the result.
// Only what is on screen can be hit.
// Requires global samplers depthtex0 and colortex0-3, sky.glsl, shadow.glsl and, with ray
// traced block light, rt_light.glsl.
#ifndef VD_SSGI_INCLUDED
#define VD_SSGI_INCLUDED 1

uint giRngState = 1u;
// Repeats every 16 frames, like the rest of the noise of this pass.
void giSeed(ivec2 pixel) {
	giRngState = uint(pixel.x) * 1973u + uint(pixel.y) * 9277u + uint(frameCounter % 16) * 26699u + 1u;
}
float giRandom() {
	giRngState = giRngState * 747796405u + 2891336453u;
	uint word = ((giRngState >> ((giRngState >> 28u) + 4u)) ^ giRngState) * 277803737u;
	return float((word >> 22u) ^ word) / 4294967296.0;
}

vec3 giCosineDirection(vec3 N, vec2 random) {
	float z = 1.0 - 2.0 * random.x;
	float a = random.y * TAU;
	float r = sqrt(max(1.0 - z * z, 0.0));
	vec3 dir = N + vec3(r * cos(a), r * sin(a), z) * 0.999;
	float lengthSquared = dot(dir, dir);
	return lengthSquared > 1e-5 ? dir / sqrt(lengthSquared) : N;
}

// One ray through the depth buffer, with steps that grow along it. Returns the screen position
// of the first surface it passes behind, unless it passed far behind, under the object.
bool giTraceScreen(vec3 viewPos, vec3 dir, float jitter, int steps, out vec2 hitUv, out float hitDepth) {
	hitUv = vec2(0.0);
	hitDepth = 1.0;
	float rayLength = float(RT_DISTANCE);
	if (dir.z > 0.0) rayLength = min(rayLength, (-near * 1.5 - viewPos.z) / dir.z);
	if (rayLength <= 0.0) return false;

	vec3 start = screenFromView(viewPos);
	vec3 delta = screenFromView(viewPos + dir * rayLength) - start;

	// Clip to the screen, so that no steps are spent outside of it.
	float clip = 1.0;
	if (delta.x > 0.0) clip = min(clip, (1.0 - start.x) / delta.x);
	else if (delta.x < 0.0) clip = min(clip, -start.x / delta.x);
	if (delta.y > 0.0) clip = min(clip, (1.0 - start.y) / delta.y);
	else if (delta.y < 0.0) clip = min(clip, -start.y / delta.y);
	delta *= max(clip, 0.0);

	vec2 size = vec2(viewWidth, viewHeight);
	float previousS = 0.0;
	for (int i = 0; i < RT_STEPS; i++) {
		if (i >= steps) break;
		float s = (float(i) + jitter) / float(steps);
		s = s * s * 0.92 + s * 0.08;
		vec3 p = start + delta * s;
		if (p.z >= 1.0) return false;
		float sceneDepth = texelFetch(depthtex0, ivec2(p.xy * size), 0).r;
		if (sceneDepth < p.z) {
			float gap = linearDepth(p.z) - linearDepth(sceneDepth);
			if (gap < 2.0 + linearDepth(sceneDepth) * 0.06) {
				float low = previousS;
				float high = s;
				for (int j = 0; j < 2; j++) {
					float mid = 0.5 * (low + high);
					vec3 q = start + delta * mid;
					if (texelFetch(depthtex0, ivec2(q.xy * size), 0).r < q.z) high = mid;
					else low = mid;
				}
				hitUv = (start + delta * high).xy;
				hitDepth = texelFetch(depthtex0, ivec2(hitUv * size), 0).r;
				return hitDepth < 1.0;
			}
		}
		previousS = s;
	}
	return false;
}

// Light reflected towards a point from the surfaces around it, through paths that start in
// cosine weighted directions. The lighting pass multiplies it by the albedo of the point.
vec3 traceBounceLight(vec3 viewPos, vec3 N, vec2 random, float jitter, ivec2 pixel) {
	giSeed(pixel);
	vec2 size = vec2(viewWidth, viewHeight);
	vec3 sunDir = normalize(shadowLightPosition);
	vec3 sunColor = readLightColor();
	vec3 ambientUp = readAmbientUp();
	vec3 ambientSide = readAmbientSide();

	vec3 radiance = vec3(0.0);
	vec3 throughput = vec3(1.0);
	vec3 position = viewPos;
	vec3 normal = N;
	vec2 directionNoise = random;
	float stepJitter = jitter;

	for (int bounce = 0; bounce < RT_BOUNCES; bounce++) {
		vec3 dir = giCosineDirection(normal, directionNoise);
		vec2 hitUv;
		float hitDepth;
		// Deeper bounces carry far less light, so a coarser search is enough for them.
		int steps = bounce == 0 ? RT_STEPS : max(RT_STEPS / 2, 6);
		if (!giTraceScreen(position, dir, stepJitter, steps, hitUv, hitDepth)) break;

		ivec2 hitPx = ivec2(hitUv * size);
		vec4 geometry = texelFetch(colortex3, hitPx, 0);
		vec3 hitGeomNormal = decodeNormal(geometry.rg);
		// The back of a surface sends no light this way.
		if (dot(hitGeomNormal, dir) > 0.1) break;
		int hitClass = unpackMaterialClass(geometry.b);
		if (hitClass == MAT_HAND || hitClass == MAT_CLOUD) break;

		vec3 hitView = viewFromScreen(hitUv, hitDepth);
		vec3 hitFeet = viewToFeet(hitView);
		vec3 albedo = texelFetch(colortex0, hitPx, 0).rgb;
		vec4 normalLight = texelFetch(colortex1, hitPx, 0);
		vec3 hitNormal = decodeNormal(normalLight.rg);
		float emission = texelFetch(colortex2, hitPx, 0).b;
		float lmBlock = normalLight.b;
		float lmSky = normalLight.a;

		// Its own glow, in the colour of its texture: blue around soul fire, orange around lava.
		vec3 light = surfaceEmission(albedo, emission, hitClass);
#ifdef USE_RT_LIGHT
		// Light sources close by are sampled directly at the surface the ray left, so this ray
		// must not count them again. Further away that light has faded out and the ray takes over.
		if (emission > 0.02 && hitClass != MAT_UNLIT) {
			light *= mix(1.0, smoothstep(5.0, 12.0, distance(hitView, position)), rtRangeFade(hitFeet));
		}
#endif

		// Light falling on the surface that was hit.
		vec3 worldNormal = mat3(gbufferModelViewInverse) * hitNormal;
		vec3 incoming = skyAmbient(worldNormal, ambientUp, ambientSide);
#ifdef HAS_SKYLIGHT
		incoming = applySkyOcclusion(incoming, lmSky);
#endif
#ifdef HAS_SHADOWS
		float NoL = dot(hitNormal, sunDir);
		if (NoL > 0.0 && dot(hitGeomNormal, sunDir) > 0.0) {
			vec3 worldGeomNormal = mat3(gbufferModelViewInverse) * hitGeomNormal;
			float sun = shadowVisibilityFast(hitFeet + worldGeomNormal * 0.08);
#ifdef HAS_SKYLIGHT
			sun *= smoothstep(0.0, 0.18, lmSky);
#endif
			incoming += sunColor * sun * NoL * INV_PI;
		}
#endif
		float blockCurve = lmBlock * lmBlock;
		blockCurve = blockCurve * (0.22 + 1.05 * blockCurve);
		vec3 vanillaBlock = vec3(1.0, 0.52, 0.24) * blockCurve * 1.35 * float(BLOCKLIGHT_STRENGTH) / 100.0;
#ifdef USE_RT_LIGHT
		// Only the first surface gets ray traced block light, with a shadow ray towards the light.
		// It carries most of the bounce light. Deeper bounces are too faint for their shadows or
		// their exact colour to show, and use the vanilla light level, which costs nothing.
		if (bounce == 0) {
			if (lmBlock > 0.01) {
				vec4 lightNoise = vec4(giRandom(), giRandom(), giRandom(), giRandom());
				incoming += rtBlockLight(hitFeet, worldNormal, hitClass == MAT_FOLIAGE, lightNoise, true);
				incoming += vanillaBlock * rtLightmapScale(hitFeet);
			}
		} else {
			incoming += vanillaBlock;
		}
#else
		incoming += vanillaBlock;
#endif

		radiance += throughput * (light + albedo * incoming);
		throughput *= albedo;

		// Russian roulette: a path that carries little light ends at random, and a path that
		// goes on carries more, so that on average nothing is lost.
		if (bounce >= 1) {
			float survive = clamp(max(throughput.r, max(throughput.g, throughput.b)), 0.05, 0.9);
			if (giRandom() >= survive) break;
			throughput /= survive;
		}
		position = hitView + hitGeomNormal * (0.01 - hitView.z * 0.002);
		normal = hitGeomNormal;
		directionNoise = vec2(giRandom(), giRandom());
		stepJitter = giRandom();
	}
	return radiance;
}

#endif
