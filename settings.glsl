// VanillaDeluxe - user options and Iris buffer directives.
// Every option in the Shader Pack Settings menu is declared in this one file.
#ifndef VD_SETTINGS_INCLUDED
#define VD_SETTINGS_INCLUDED 1

/*
const int colortex0Format = RGBA16F;
const int colortex1Format = RGBA16;
const int colortex2Format = RGBA8;
const int colortex3Format = RGBA16;
const int colortex4Format = RGBA16F;
const int colortex5Format = RGBA16;
const int colortex6Format = RGBA16F;
const int colortex7Format = RGBA16F;
const int colortex8Format = RGBA16F;
const int colortex9Format = RGBA16F;
const int colortex10Format = RGBA16F;
const int colortex11Format = RGBA16F;
const int colortex12Format = RGBA16F;
const int colortex13Format = RGBA32F;
const int colortex14Format = RGBA32F;
const int colortex15Format = RGBA8;
const int colortex16Format = RGBA16F;
const int colortex19Format = RGBA16F;
const int shadowcolor0Format = RGBA8;

const bool colortex1Clear = false;
const bool colortex2Clear = false;
const bool colortex3Clear = false;
const bool colortex6Clear = false;
const bool colortex7Clear = false;
const bool colortex8Clear = false;
const bool colortex9Clear = false;
const bool colortex10Clear = false;
const bool colortex11Clear = false;
const bool colortex12Clear = false;
const bool colortex13Clear = false;
const bool colortex14Clear = false;
const bool colortex19Clear = false;

const vec4 colortex0ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
const vec4 colortex4ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
const vec4 colortex5ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
const vec4 colortex15ClearColor = vec4(1.0, 1.0, 1.0, 1.0);
const vec4 colortex16ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
const vec4 shadowcolor0ClearColor = vec4(1.0, 1.0, 1.0, 1.0);

const bool shadowHardwareFiltering1 = true;
const bool shadowtex0Nearest = true;
const bool shadowcolor0Nearest = true;

const int noiseTextureResolution = 256;
const float wetnessHalflife = 240.0;
const float drynessHalflife = 80.0;
const float eyeBrightnessHalflife = 8.0;
const float ambientOcclusionLevel = 1.0;
const float shadowDistanceRenderMul = 1.0;
const float shadowIntervalSize = 2.0;
const float voxelDistance = 64.0;
*/

// ---- Ray tracing ----------------------------------------------------------
// The defaults below are the Medium ray tracing profile, which makes it the standard.
// tools/build.py checks that they stay identical.
#define RAY_TRACING // Ray traced light, with a temporal and a spatial denoiser
#define RT_BLOCK_LIGHT // Torches, glowstone and lava cast ray traced coloured light and shadows
#define SCREEN_SPACE_GI // Bounce light from the visible scene
//#define RT_COLOR_TRACING // Light takes the real colour of its source and of stained glass
#define RT_BOUNCES 1 // [1 2 3 4 6 8 12 16 24]
#define RT_DISTANCE 32 // [16 32 64 128 256]
#define RT_STEPS 12 // [8 12 16 24 32 48]
#define DENOISER_RADIUS 2 // [1 2 3 4]
#define RT_LIGHT_FILL 0 // [0 15 30 50 75 100]

// ---- Shadows ------------------------------------------------------------
const int shadowMapResolution = 2048; // [1024 1536 2048 3072 4096 6144 8192]
const float shadowDistance = 96.0; // [48.0 64.0 80.0 96.0 112.0 128.0 160.0 192.0 224.0 256.0]
const float sunPathRotation = -35.0; // [-60.0 -50.0 -45.0 -40.0 -35.0 -30.0 -25.0 -20.0 -15.0 -10.0 -5.0 0.0 5.0 10.0 15.0 20.0 25.0 30.0 35.0 40.0 45.0 50.0 60.0]
const float entityShadowDistanceMul = 0.5; // [0.25 0.5 0.75 1.0]

#define VARIABLE_PENUMBRA // Contact-hardening soft shadows
#define SHADOW_BLOCKER_SAMPLES 6 // [4 6 8 12 16 24]
#define SHADOW_FILTER_SAMPLES 8 // [4 6 8 12 16 24 32]
#define SHADOW_PENUMBRA_SIZE 100 // [25 50 75 100 125 150 200 300]
#define COLORED_SHADOWS // Light tinted through stained glass and water
#define SUBSURFACE_SCATTERING // Light transmitted through leaves and plants
#define CLOUD_SHADOWS // Volumetric clouds shade the ground

// ---- Lighting -----------------------------------------------------------
#define SCREEN_SPACE_AO // Horizon-based ambient occlusion
#define AO_STEPS 4 // [3 4 6 8 10 12 16]
#define AO_RADIUS 25 // [10 15 20 25 30 40 50 60]
#define AO_STRENGTH 100 // [25 50 75 100 125 150 200]
#define GI_STRENGTH 100 // [25 50 75 100 125 150 200 300]
#define SUN_STRENGTH 100 // [25 50 75 100 125 150 200 300]
#define AMBIENT_STRENGTH 100 // [25 50 75 100 125 150 200 300]
#define BLOCKLIGHT_STRENGTH 100 // [25 50 75 100 125 150 200 300]
#define EMISSION_STRENGTH 100 // [25 50 75 100 125 150 200 300 400]
#define MIN_LIGHT 100 // [0 50 100 150 200 300 400]
#define HAND_DYNAMIC_LIGHT // Held torches and lanterns light the world

// ---- Materials ----------------------------------------------------------
#define PBR_FORMAT 1 // [0 1 2]
#define NORMAL_MAPPING // Use the normal map of the resource pack
#define GENERATED_NORMALS // Derive surface detail from vanilla textures
#define GENERATED_NORMAL_STRENGTH 100 // [25 50 75 100 125 150 200 300]
#define PARALLAX_OCCLUSION // Parallax occlusion mapping for height maps
#define POM_SAMPLES 24 // [16 24 32 48 64 96 128]
#define POM_DEPTH 25 // [5 10 15 20 25 30 40 50 75 100]
#define POM_DISTANCE 32 // [8 16 24 32 48 64 96]
#define POM_SELF_SHADOW // Height maps cast small shadows on themselves
#define SPECULAR_HIGHLIGHTS // Sun and moon highlights on surfaces
#define INTEGRATED_EMISSION // Glowing pixels for light sources without a PBR pack
#define WET_SURFACES // Surfaces darken and shine in the rain
#define WAVING_PLANTS // Wind moves grass and flowers
#define WAVING_LEAVES // Wind moves leaves

// ---- Material effects ---------------------------------------------------
#define LAVA_EMISSIVE_BRIGHTNESS 1.0 // [0.5 0.75 1.0 1.25 1.5 1.75 2.0]
#define ICE_REFLECTIVITY // Glossy ice with screen-space reflections
#define GLASS_REFLECTIONS // Fresnel and screen-space reflections on glass

// ---- Water --------------------------------------------------------------
#define WATER_WAVES // Procedural surface waves
#define WATER_WAVE_HEIGHT 100 // [25 50 75 100 125 150 200 300]
#define WATER_WAVE_SPEED 100 // [25 50 75 100 125 150 200]
#define WATER_WAVE_OCTAVES 8 // [4 6 8 10 12 16]
#define WATER_REFRACTION // Water, ice and glass bend the view of what is behind them
#define WATER_CAUSTICS // Light patterns under water
//#define WATER_FOAM // Foam along shores
#define WATER_ABSORPTION 100 // [25 50 75 100 125 150 200 300]

// ---- Reflections --------------------------------------------------------
#define SCREEN_SPACE_REFLECTIONS // Screen-space reflections on water and glass
#define SSR_ON_SURFACES // Also reflect on smooth PBR surfaces
#define ROUGH_REFLECTIONS // Rough surfaces scatter their reflections
#define SSR_STEPS 16 // [12 16 24 32 48 64]
#define SSR_REFINE 3 // [2 3 4 6 8]

// ---- Atmosphere ---------------------------------------------------------
#define VOLUMETRIC_LIGHT // God rays from raymarching the shadow map
#define VL_STEPS 8 // [6 8 10 12 16 24 32]
#define VOLUMETRIC_CHECKERBOARD // Fog, god rays and clouds march half of their pixels per frame, history fills in the rest
#define VL_STRENGTH 100 // [25 50 75 100 125 150 200 300]
#define FOG_DENSITY 100 // [25 50 75 100 125 150 200 300 400]
#define VOLUMETRIC_CLOUDS // Raymarched clouds, replaces vanilla clouds

// ---- Smoke and fog --------------------------------------------------------
#define VOLUMETRIC_SMOKE // Torches, fires and lava give off rising volumetric smoke
#define VOLUMETRIC_FOG // Mist in deep caves, fog that rolls in with rain, and thick Nether fog
#define CAVE_FOG_DENSITY 100 // [0 25 50 75 100 150 200 300]
#define WEATHER_FOG_INTENSITY 100 // [0 25 50 75 100 150 200 300]
#define NETHER_FOG_DENSITY 100 // [0 25 50 75 100 150 200 300]

// ---- Weather --------------------------------------------------------------
#define RAIN_REFRACTION // Raindrops bend the light from what is behind them
#define RAIN_OPACITY 100 // [25 50 75 100 150 200]
#define WEATHER_SPLASH_QUALITY 2 // [0 1 2 3]
#define SNOW_WIND_DRIFT 100 // [0 25 50 75 100 150 200 300]
#define SNOW_QUALITY 1 // [1 2]
#define GLASS_WEATHER_EFFECTS // Raindrops run down windows, and frost grows on them in snow
#define GROUND_SPLASH_PARTICLES // Tiny droplets jump up where rain hits the ground
#define CLOUD_STEPS 10 // [8 10 14 18 24 32 48]
#define CLOUD_SUN_STEPS 3 // [2 3 4 6 8]
#define CLOUD_ALTITUDE 220 // [128 160 192 220 256 320 384 512]
#define CLOUD_THICKNESS 120 // [40 60 80 100 120 160 200 300]
#define CLOUD_COVERAGE 50 // [20 30 40 45 50 55 60 70 80]
#define CLOUD_SPEED 100 // [0 25 50 100 150 200 400]
#define SUNSET_CRIMSON 80 // [0 20 40 60 80 100]
#define SKY_BRIGHTNESS 100 // [50 75 100 125 150 200]

// ---- Camera effects (1.10.0) ---------------------------------------------
//#define DEPTH_OF_FIELD // Blur in front of and behind what is in the middle of the screen
#define DOF_STRENGTH 100 // [25 50 75 100 150 200 300]
//#define TILT_SHIFT // Miniature look: a soft blur at the top and bottom of the screen
#define TILT_SHIFT_STRENGTH 100 // [25 50 75 100 150 200 300]
#define TILT_SHIFT_BAND 30 // [10 20 30 40 50]
#define LENS_FLARE // Ghosts and a starburst when looking towards the sun or moon
#define LENS_FLARE_STRENGTH 100 // [25 50 75 100 150 200 300]
#define LENS_DIRT // Smudges on the lens light up around bright lights
#define LENS_DIRT_STRENGTH 100 // [25 50 75 100 150 200 300]

// ---- Dimensions (1.10.0) -------------------------------------------------
#define NETHER_HEAT_HAZE // Hot air shimmers high above the lava seas of the Nether
#define NETHER_LIGHT_SHAFTS // Glowstone and fire cast shafts of coloured light through Nether fog
#define END_AURORA // Curtains of blue and violet light wave across the sky of the End
#define END_AURORA_BRIGHTNESS 100 // [25 50 75 100 150 200 300]
#define END_CRYSTAL_RAYS // End crystals glow and send turning rays of light into the dark

// ---- PBR and physics (1.10.0) --------------------------------------------
#define DYNAMIC_PUDDLES // Puddles fill dips in the ground first and dry up in the sun
#define PUDDLE_AMOUNT 100 // [25 50 75 100 150 200]
#define SSS_STRENGTH 100 // [25 50 75 100 150 200 300]

// ---- Post processing ----------------------------------------------------
#define TEMPORAL_AA // Temporal anti-aliasing and denoising
#define TAA_SHARPEN 40 // [0 20 30 40 50 60 80 100]
#define BLOOM // Bright light bleeds into its surroundings
#define BLOOM_STRENGTH 100 // [25 50 75 100 125 150 200 300]
#define CHROMATIC_ABERRATION // Subtle lens colour fringing at the screen edge
#define CA_STRENGTH 100 // [25 50 75 100 150 200 300]
#define VIGNETTE // Darkens the corners of the screen
#define TONEMAP 1 // [0 1 2]
#define LOOK_PROFILE 1 // [0 1 2]
#define AUTO_EXPOSURE // Eyes adapt between caves and daylight
#define EXPOSURE_COMPENSATION 0 // [-20 -15 -10 -5 0 5 10 15 20]
#define SATURATION 100 // [50 75 90 100 110 125 150]
#define CONTRAST 100 // [75 90 100 110 125 150]

// Iris only offers a boolean option if it is tested with ifdef or ifndef somewhere.
// These are otherwise only used in combined conditions.
#ifdef SCREEN_SPACE_GI
#endif
#ifdef CLOUD_SHADOWS
#endif
#ifdef PARALLAX_OCCLUSION
#endif
#ifdef WATER_CAUSTICS
#endif
#ifdef SSR_ON_SURFACES
#endif
#ifdef VOLUMETRIC_LIGHT
#endif
#ifdef RT_BLOCK_LIGHT
#endif
#ifdef RT_COLOR_TRACING
#endif
#ifdef GLASS_WEATHER_EFFECTS
#endif
#ifdef NETHER_HEAT_HAZE
#endif
#ifdef NETHER_LIGHT_SHAFTS
#endif
#ifdef END_CRYSTAL_RAYS
#endif
#ifdef DEPTH_OF_FIELD
#endif
#ifdef TILT_SHIFT
#endif
#ifdef VOLUMETRIC_CHECKERBOARD
#endif
#ifdef GROUND_SPLASH_PARTICLES
#endif
#ifdef VOLUMETRIC_FOG
#endif

// What actually runs. The ray traced features all write into the half resolution indirect
// light, which the temporal and spatial denoisers then clean up.
#if defined RAY_TRACING && defined RT_BLOCK_LIGHT
#define USE_RT_LIGHT 1
#endif
#if defined RAY_TRACING && defined SCREEN_SPACE_GI
#define USE_RT_GI 1
#endif
#if defined USE_RT_LIGHT && defined RT_COLOR_TRACING
#define USE_COLOR_TRACING 1
#endif
#if defined SCREEN_SPACE_AO || defined USE_RT_LIGHT || defined USE_RT_GI
#define USE_INDIRECT 1
#endif
// The voxel scene and its list of light sources. Volumetric smoke rises from the listed fires,
// torches and lava, so it needs the list even without ray traced light.
#if defined USE_RT_LIGHT || defined VOLUMETRIC_SMOKE
#define USE_LIGHT_LIST 1
#endif
// The weather map: the highest block of every column near the player, built by the shadow pass of
// the overworld. Every weather effect checks it, so nothing under a roof gets wet or snowed on.
#if DIM_ID == 0
#define USE_WEATHER_MAP 1
#endif
// Snow and the splash droplets are drawn procedurally in the final pass. Rain is the vanilla
// rain, shaded by gbuffers_weather as in v1.9.0.
#define USE_PRECIPITATION 1

#endif
