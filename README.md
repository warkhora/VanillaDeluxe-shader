# VanillaDeluxe 1.11.0 – Performance & Polish Update

A shaderpack for Minecraft Java 26.2 using Iris 1.11.4 or newer and Sodium. It features photorealistic lighting with a dark, warm, and reddish character, designed for high performance.

## Installation

1. Install Fabric with Iris and Sodium for Minecraft 26.2. Iris 1.11.4 or newer is required.
2. Place `VanillaDeluxe_v1.11.0.zip` into the `shaderpacks` folder in your `.minecraft` directory. Do not extract it.
3. In-game: Go to **Options → Video Settings → Shader Packs**, select VanillaDeluxe, and click **Apply**.

**Important:** Iris does not support Vulkan. If your **Graphics API** in video settings is set to Vulkan, you must change it to Default or Prefer OpenGL.

## Ray Tracing and Profiles

Select your profile at the top of **Shader Pack Settings** or in the **Ray Tracing** menu. Profiles only control ray tracing. Shadows, clouds, and everything else are configured in their respective menus.

| Profile | What it does | GPU Time in Test Rig, 1440p |
|---|---|---|
| **Off** | Standard Minecraft lighting with ambient occlusion | 3.4–3.8 ms |
| **Low** | Ray-traced lighting and shadows from torches, glowstone, and lava | +0.4–1.0 ms |
| **Medium** (default) | Same as Low, plus bounce lighting with 1 bounce and 2 chunks range | similar to previous version |
| **High** | 3 bounces, 4 chunks range, and Advanced Color Tracing | +0.5–0.9 ms over Medium |
| **Ultra** | Up to 24 bounces, 16 chunks range, and Advanced Color Tracing | +0.8–1.7 ms over Medium |

In the menu, you can also individually adjust **Light Bounces** (1–24), **Ray Distance** (1–16 chunks), **Steps per Ray**, **Denoiser Width**, and **Soft Fill Light**.

**Ray-Traced Block Light.** The shadow pass places blocks into a voxel scene of 128 × 64 × 128 blocks around the player and lists each light source. Each pixel at half resolution selects a nearby light source and casts one shadow ray toward it. The light also works when the light source is off-screen. Where the light does not reach, it is as dark as if the light source did not exist (with **Soft Fill Light** at 0%, which is the default).

**Bounce Lighting.** Each pixel at half resolution follows a single path through the depth buffer. Each surface the path hits is illuminated on the spot by its own glow, the sun, the sky, and block light, passing the light along in its own color. A red wall thus casts red light, which a white floor passes on. Weak paths terminate early, so many bounces cost less than it sounds.

**Advanced Color Tracing.** Each light source emits light in the color of its own texture—for example, deep blue around soul torches and red around redstone—and colored glass tints the light passing through it. The color is stored in the voxel scene, making it almost free to compute.

**Denoiser.** Light is accumulated over time (about a third of a second) and then filtered in two spatial passes that stop at depth and normal edges. They also stop at light differences larger than the noise measured in each pixel, keeping shadow edges sharp. All noise repeats in short cycles that the filter smooths out entirely, preventing shadows from flickering when the camera stands still.

**Limitations:**
- Only objects on screen can be hit by bounce lighting. Direct lighting from light sources also works off-screen.
- Outside the voxel scene (about 50 blocks horizontally and 20 blocks vertically), lighting falls back to standard block light without shadows.
- Entities and mobs are illuminated, but do not cast shadows from block light. Half-blocks like stairs and slabs attenuate light instead of stopping it precisely along their shape.
- Only the first bounce receives shadows from block light. Deeper bounces use the standard light level, as they are too weak for shadows to be visible.
- The old holistic profiles (Ultra Fast, Low, Medium, High) have been replaced by ray tracing profiles. Iris only supports a single profile list.

The path tracing version remains untouched in `archive/VanillaDeluxe-path-tracing.zip`.

## Smoke and Fog

The **Smoke & Fog** menu contains these settings:

- **Volumetric Smoke**: Torches, campfires, fire, and lava emit smoke that rises, swirls, and picks up the glow from its source. It replaces the flat grey smoke particles above them. Smoke uses the light source list from the voxel scene, so it works even with ray tracing disabled.
- **Volumetric Fog**:
  - Floating haze in deep caves, becoming denser the deeper you are, illuminated by surrounding torches and lava.
  - Fog banks rolling in with rain, becoming denser during thunderstorms.
  - Thick fog in the Nether, colored to match the biome and glowing orange over the lava sea.
- **Cave Haze Density**, **Weather Fog Intensity**, and **Nether Fog Density** ranging from 0% to 300%.

Everything is calculated in the same volumetric pass as sunshafts, at half resolution with temporal filtering. Therefore, it does not require an extra pass.

**Limitations:**
- Smoke only originates from light sources within the voxel scene (about 50 blocks away).
- Iris does not expose which particles are smoke. Grey particles directly above a smoke source are removed, while sparks and flames remain.
- Cave haze knows you are underground based on how much sky is visible, matching vanilla game behavior.
- Lava smoke is read directly from lava blocks in the voxel scene. It is therefore identical from frame to frame, regardless of the order in which the GPU renders blocks.

## Weather

The **Weather & Materials** menu (also under **Smoke & Fog**) contains these settings:

- **Rain and Snow**: Rain uses the rain style from 1.9.0: vanilla streaks with light refraction, wind drift, and torch light. Snow is rendered by the pack in true depth using 3D Smooth (default) or Ultra with multiple layers further away. Vanilla ground splashes are filtered out in the particle pass.
- **Weather on Glass**: During rain, droplets sit on windows and slowly slide down, refracting what you see through and in the glass. During snow, a narrow, uneven frost border grows inward from the edges of the panes, scaling with the snowfall intensity.
- **Rain Splashes**: Small droplets bounce low where rain hits the ground. Heavier rain and storms produce more and higher droplets.

- **Rain Light Refraction**: Each raindrop refracts the image behind it. This is done in the final image after TAA, keeping the streaks sharp. Droplets catch light from the sun and moon, and from torches in their own color via ray tracing.
- **Rain Visibility**: How clearly rain is rendered.
- **Rain Ripples**: Off, Low, Medium, or High. Raindrops create ripples in water, puddles, and on wet ground, visible in reflections.
- **Snow Wind Drift**: How hard the wind blows and swirls the snow. Snowflakes light up near torches and lava.

During storms, rain slants in the wind, cloud cover closes in, sun and sky light dim, and haze and fog thicken—most severely during thunderstorms. Snowstorms produce brighter and whiter fog than rain.

**Limitations:**
- Vanilla splash particles are retained. Ripples are rendered on surfaces rather than as separate particles.
- Snow and rain are determined based on the biome you are standing in, as reported by Iris.

Under **Appearance** you will find:

- **VanillaDeluxe / Dark Red** (default), **Natural Warm**, or **Neutral**
- **AgX** or **ACES** as tonemapping options
- Menu tabs for **Ray Tracing**, **Smoke & Fog**, **Lighting**, and **Materials** with color codes
- **Sunset Depth** to control how red sunsets appear

## What's New in 1.11.0

- **Rain from 1.9.0 is back.** Vanilla ground splashes are removed: Iris can only disable them alongside the rain itself, so the particle pass recognizes them as bluish particles directly on top of the ground where it is raining.
- **Depth of Field is off by default**, ensuring the image is completely sharp.
- **Tilt-shift / Miniature** under **Camera Effects**: Soft blur at the top and bottom of the screen with a sharp horizontal band across the middle. Both the strength and height of the band are adjustable.
- **Performance:**
  - Volumetrics (fog, sunshafts, clouds, and smoke) are rendered in a checkerboard pattern (half of the pixels per frame), filled in by the temporal filter. Volumetrics were already running at half resolution.
  - Secondary bounces use half as many search steps.
  - Lens flare is measured once per frame instead of per pixel, and lens dirt is calculated only where light shines.
  - The **Off** and **Low** profiles also use lighter shadows, reflections, volumetrics, POM, and waves for older GPUs. Medium, High, and Ultra remain unchanged.

## What's New in 1.10.0

**Weather only where it actually rains.** The shadow pass creates a heightmap of the topmost block in each column within 64 blocks. All weather effects check it: rain, snow, splashes, ripples, wet ground, puddles, and droplets on glass. Areas under a roof remain dry, including right inside the roof edge. Beyond the heightmap range, the sky light level is used as before.

**Camera Effects** (the **Camera Effects** menu):
- **Depth of Field** with autofocus on whatever is in the center of the screen. Focus tracks smoothly, and the handheld item is always kept sharp.
- **Lens Flare** from the sun and moon, occluded by clouds and foreground terrain.
- **Lens Dirt**, which only lights up around bright light sources.

**Dimensions** (the **Dimensions** menu):
- **Nether**: Enhanced heat haze high above lava seas. Fog takes on the color of nearby lights, and glowstone and fire cast light shafts through it. Light shafts require ray-traced block light.
- **End**: **Void Aurora**, undulating curtains of blue and violet light. **End Crystals** glow and cast slowly rotating light shafts out into the dark.

**PBR and Physics** (the **PBR & Physics** menu):
- **Dynamic Puddles**: Water first collects in depressions where surrounding terrain is higher, gradually spreading to flat ground. After rain, puddles shrink again, faster under the sun.
- **Subsurface Scattering** was previously available. It now features a dedicated intensity setting, and the undersides of leaves let some sky light through, keeping them green instead of grey.

**Limitations:**
- End crystals are detected via `entity.properties`. If Iris does not assign them an ID, they glow normally, but the light shafts will be missing.
- With older versions of Iris that cannot disable vanilla weather, vanilla weather will still not be visible, but splash particles might reappear.
- The heightmap is built from what the shadow pass renders. Blocks outside shadow distance are missing from the map, causing weather effects to fall back to the sky light level there.

## Features

**Lighting and Materials**
- labPBR and seusPBR: normals, specular, roughness, metals, emission, porosity, and subsurface scattering
- Parallax occlusion mapping with self-shadowing
- Built-in materials giving vanilla textures gloss, metal, and emission without a PBR resource pack
- Ambient occlusion with visibility bitmask and ray-traced bounce lighting (1–24 bounces) at half resolution with temporal accumulation and a noise-driven spatial denoiser
- Wet surfaces and puddles during rain, plus dynamic hand-held lighting

**Shadows**
- Contact-hardening shadows: sharp at contact points, softer with distance
- Colored shadows through glass, underwater caustics, and light filtering through foliage

**Atmosphere**
- Physically based Rayleigh, Mie, and ozone scattering calculated in a small sky LUT every frame
- Sunshafts, height fog, and volumetric clouds with cloud shadows

**Water and Reflections**
- Procedural waves, Fresnel, light refraction, and depth coloring, with optional foam along shores
- Water is only illuminated by light that actually reaches it, making it pitch black when no light sources are nearby
- Screen-space reflections on water, glass, metal, polished, and wet surfaces

**Material Effects** (dedicated menu)
- Lava: Pulsing emission with a dedicated slider, gloss on molten areas, and heat haze in the air above
- Ice: Glossy surface with reflections and light refraction. Regular ice is transparent with a cold tint, while packed ice and blue ice only reflect, being massive blocks
- Glass: Fresnel reflections from both sides of the pane and physically calculated light refraction, including clear window sections

**Image**
- TAA with Catmull-Rom and variance clipping, which also denoises sampled effects
- AgX and ACES, bloom, subtle chromatic aberration, automatic exposure, and scotopic night vision

The Nether and End feature dedicated lighting setups. The Nether runs without a shadow pass, saving significant GPU time.

## How the Pack is Tested

Tests are run without Minecraft using the tools in `tools/`:

- **Compilation:** All programs across all three dimensions are compiled and linked with the NVIDIA driver across all settings: all profiles, every toggle, and boundary values.
- **Execution:** A test rig (`tools/harness`) runs the full pipeline on a synthetic world with the exact same order, buffer flipping, and shadow matrices as Iris's source code.
- **Static Checks:** `tools/build.py lint` checks uniforms, menus, language files, and reserved names.

**Not tested in-game.** Iris's shader translator (glsl-transformer) does not run in the test rig, and Minecraft-specific geometry such as entities and particles are only represented in simplified form.

If something fails in-game: Press **Ctrl+D** on the Shader Packs screen to enable debugging, reload the pack, and check `logs/latest.log` for error messages. Translated shader code will be output to the `patched_shaders` folder.

## Development

```bash
python tools/build.py zip
Markdown
## Development

```bash
python tools/build.py zip
Bash
dotnet run --project tools/harness -c Release -- compile
Bash
dotnet run --project tools/harness -c Release -- render --scene sunset
tools/build.py creates program stubs in world0, world-1, and world1, and writes VanillaDeluxe.zip to the root of the project folder. The actual code resides in shaders/program and shaders/lib, and all configuration options are in shaders/lib/settings.glsl. The test rig uses the copy of shaders located in the parent directory of the program file, and scenes can be selected using --scene: day, sunset, dusk, night, rain, pool, shore, underwater, cave, forest, pavilion, or moving.

Credits and References
All code was written specifically for this pack. The visual style was inspired by Complementary Unbound, but no code was copied from it. The following published methods were used:

Hillaire 2020: Atmosphere coefficients

Therrien et al. 2023: Indirect lighting with visibility bitmasks

Stephen Hill: ACES fitting

Benjamin Wrensch: AgX fitting

Jorge Jimenez: Interleaved gradient noise and 5-point Catmull-Rom sampling
