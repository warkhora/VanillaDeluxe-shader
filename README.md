# VanillaDeluxe 1.11.0 – Performance & Polish Update

A shader pack for Minecraft Java 26.2 with Iris 1.11.4 or newer and Sodium. It brings photorealistic
lighting with a dark, warm, slightly red character, hybrid ray tracing, volumetric weather and
smoke, and it is built to run fast.

The menus and option descriptions are in English by default. A Norwegian translation is included and
is used automatically when the game language is set to Norwegian Bokmål.

## Installation

1. Install Fabric with Iris and Sodium for Minecraft 26.2. Iris 1.11.4 or newer is required.
2. Put `VanillaDeluxe_v1.11.0.zip` into the `shaderpacks` folder of your Minecraft folder. Do not unzip it.
3. In game: **Options → Video Settings → Shader Packs**, select VanillaDeluxe and press **Apply**.

**Important:** Iris does not support Vulkan. If **Graphics API** in the video settings is set to
Vulkan, change it to Default or Prefer OpenGL. macOS is not supported, because the pack needs
OpenGL 4.2 image access.

## Ray tracing and profiles

Choose a profile at the top of **Shader Pack Settings** or in the **Ray Tracing** menu.

| Profile | What it does |
|---|---|
| **Off** | Vanilla lighting with ambient occlusion, and lighter shadows, reflections and volumetrics |
| **Low** | Ray traced light and shadows from torches, glowstone and lava, with the lighter settings of Off |
| **Medium** (default) | Low plus bounce light, 1 bounce and 2 chunks of reach |
| **High** | 3 bounces, 4 chunks of reach and Advanced Color Tracing |
| **Ultra** | Up to 24 bounces, 16 chunks of reach and Advanced Color Tracing |

The menu also lets you set **Light Bounces** (1–24), **Ray Distance** (1–16 chunks), **Ray Steps**,
**Denoiser Width** and **Soft Fill Light** on their own.

**Ray traced block light.** The shadow pass writes the blocks around the player into a voxel scene of
128 × 64 × 128 blocks and lists every light source. Every pixel, at half resolution, picks one light
nearby and traces one shadow ray towards it. The light works even when its source is off screen.
Where it cannot reach, it is as dark as if the light were not there.

**Bounce light.** Every pixel at half resolution follows one path through the depth buffer. Each
surface on the path is lit right there by its own glow, the sun, the sky and block light, and passes
the light on in its own colour: a red wall casts red light, which a white floor passes on. Weak paths
end early, so many bounces cost less than it sounds.

**Advanced Color Tracing.** Every light shines in the colour of its own texture, such as a deep blue
around soul torches and red around redstone, and stained glass colours the light that passes through.

**Denoiser.** Light is accumulated over about a third of a second, then filtered in two spatial passes
that stop at edges in depth and normal, and at changes in brightness larger than the noise measured in
each pixel, so shadow edges stay sharp.

**Limitations:**
- Bounce light can only hit what is on screen. Direct light from light sources also works off screen.
- Beyond the voxel scene, about 50 blocks sideways and 20 up or down, light falls back to vanilla block
  light without shadows.
- Mobs and players are lit, but cast no shadows from block light.

## Weather

The **Weather & Materials** menu:

- **Rain and snow**: rain is the vanilla rain, shaded by the pack with refraction, wind drift and the
  light of nearby torches. Snow is drawn by the pack in real depth, as soft flakes that drift with the
  wind: 3D Smooth (default) or Ultra with more layers further away. The vanilla rain splashes on the
  ground are filtered out.
- **Weather on Glass**: in rain, drops sit on windows and run slowly down them. In snow, a thin, ragged
  rim of frost grows in from the edges of the panes.
- **Rain Splashes**: tiny droplets jump up where rain hits the ground, more and higher in heavy rain.
- **Rain Ripples**: rings in water, puddles and wet ground, visible in the reflections.

A weather map, built from the highest block of every column within 64 blocks, keeps every weather
effect away from places under a roof: the ground there stays dry. Puddles gather in dips in the ground
first and dry up again after the rain, faster in the sun. In storms the rain leans with the wind, the
clouds close, sunlight and skylight dim and the fog thickens.

## Smoke and fog

The **Smoke & Fog** menu:

- **Volumetric Smoke**: torches, campfires, fire and lava give off rising, curling smoke lit by its source.
- **Volumetric Fog**: mist in deep caves, fog banks that roll in with rain, and thick glowing Nether fog.
- Sliders for cave mist, weather fog and Nether fog, from 0 to 300 %.

Fog, god rays, clouds and smoke are computed at half resolution in a checkerboard: half of those pixels
each frame, with the temporal filter filling in the rest.

## Camera effects

- **Depth of Field**, off by default, with autofocus on the middle of the screen.
- **Tilt-Shift / Miniature Mode**: a soft blur at the top and bottom of the screen.
- **Lens Flare** from the sun and moon, and **Lens Dirt** that lights up around bright lights.

## Dimensions

- **Nether**: strong heat haze above lava seas. The fog takes on the colour of the lights in it, and
  glowstone and fire cast shafts of light through it.
- **The End**: the **Void Aurora**, curtains of blue and violet light, and End crystals that glow and
  send turning rays of light into the dark.

## Other features

- labPBR and seusPBR, parallax occlusion mapping with self shadowing, and built-in materials so vanilla
  textures get gloss, metal and glow without a resource pack
- Contact-hardening shadows, coloured shadows through glass, caustics, and sunlight through leaves
- Physically based sky with Rayleigh, Mie and ozone scattering, and volumetric clouds with cloud shadows
- Procedural water waves, Fresnel, refraction and depth colour, and screen-space reflections on water,
  glass, metal, polished and wet surfaces
- Lava with pulsing glow and heat shimmer, glossy ice and physically refracting glass
- TAA, AgX or ACES tonemapping, bloom, automatic exposure and scotopic night vision

## How the pack is tested

The tests run outside Minecraft, with the tools in `tools/`:

- **Compiling:** every program in all three dimensions is compiled and linked with the NVIDIA driver
  over every set of options: all profiles, every switch on and off, and extreme values.
- **Rendering:** a test harness (`tools/harness`) runs the whole pipeline on a synthetic world, in the
  same order and with the same buffer flipping and shadow matrices as Iris.
- **Static checks:** `tools/build.py lint` checks uniforms, menus, language files and reserved names.

If something fails in game: press **Ctrl+D** on the Shader Packs screen to turn on debugging, reload
the pack and look for errors in `logs/latest.log`.

## Development

```bash
python tools/build.py zip
```

```bash
dotnet run --project tools/harness -c Release -- compile
```

```bash
dotnet run --project tools/harness -c Release -- render --scene sunset
```

`tools/build.py` generates the program stubs in `world0`, `world-1` and `world1` and writes
`VanillaDeluxe_v<version>.zip` in the project folder. The code is in `shaders/program` and `shaders/lib`,
and every option is in `shaders/lib/settings.glsl`.

## Credits

All code was written for this pack. The look is inspired by Complementary Unbound, but no code was taken
from it. These published methods are used:

- Hillaire 2020: atmosphere coefficients
- Therrien et al. 2023: indirect light with a visibility bitmask
- Stephen Hill: ACES fit
- Benjamin Wrensch: AgX fit
- Jorge Jimenez: interleaved gradient noise and five-tap Catmull-Rom sampling

## License

MIT License. See `LICENSE.txt`.
