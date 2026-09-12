# HighFrames+

A Minecraft shader pack built from scratch.

## How it works

All shaders are written in **GLSL** (OpenGL Shading Language), version 330 compatibility profile. The pack targets **Iris** / **OptiFine** on Minecraft Java Edition.

## File structure

```
shaders/
├── library/            shared code included by other files
│   ├── distort.glsl    shadow distortion math
│   ├── time.glsl       day/night cycle, light colors
│   ├── sky.glsl        sky gradient and sun glow
│   ├── pad.glsl        utility functions
│   └── basic.vsh       shared vertex setup
│
├── world/              overworld shaders
│   ├── gbuffers_terrain.*    solid blocks (grass, stone, etc.)
│   ├── gbuffers_water.*      water rendering
│   ├── gbuffers_entities.*   entities and item frames
│   ├── gbuffers_hand.*       held items
│   ├── gbuffers_skybasic.*   sky color
│   ├── gbuffers_skytextured.* moon, sun
│   ├── gbuffers_textured_lit.* general lit textures
│   ├── shadow.*              shadow map pass
│   ├── deferred.*            main lighting pass
│   ├── deferred1.*           distance fog
│   ├── composite.*           underwater tint
│   ├── composite1.*          screen-space reflections
│   └── final.*               post-processing, color grading
│
├── nether/             nether dimension shaders
├── the-end/            end dimension shaders
├── shaders.properties  pack settings (shown in Iris menu)
└── block.properties    block type definitions for masks
```

## Render pipeline

1. **gbuffers** — Each geometry type renders to its own buffer (color, lightmap, normals, entity mask)
2. **shadow** — Renders the scene from the sun's perspective into a depth map
3. **deferred** — Applies lighting and shadows to all solid blocks using the shadow map
4. **composite** — Adds underwater tinting and foam
5. **composite1** — Screen-space reflections for water and reflective surfaces
6. **deferred1** — Distance fog
7. **final** — Tone mapping, saturation, color tinting, and any screen effects

## Settings

All options are in the Iris shader settings menu under labeled sections. Toggles use on/off, sliders use numeric ranges.

## License

CC BY 4.0 — see [LICENSE](LICENSE) for details.
