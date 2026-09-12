# Wispy Shaders V1.4

A performance-optimized shader pack initially based on Mellow Shaders and outperforms many other so claimed 'potato' shaders. Works on all major versions. Also follow for updates.

## Credits

*   **Original Shader**: [Mellow Shaders](https://www.curseforge.com/minecraft/shaders/mellow) by [TheCMK](https://www.curseforge.com/members/thecmk/)
*   **Performance Optimizations**: [l\_aggy](https://www.curseforge.com/members/l_aggy/projects)

## Features

(All information and statistics is based on V1.3)

*   **Ultra-optimized** for integrated graphics (iGPUs)
*   **40%+** improvement on Balanced compared to MakeUp-Ultrafast with all effects off
*   **Color grading** and biome‑specific lighting for all dimensions.
*   **Cinematic post‑processing**: bloom, sharpening, tonemapping, TAA, motion blur, vignette.

## To-do

1.  More benchmarking
2.  Adding features (Can't really optimize more)
3.  Bugfix some features

## Performance Profiles

*   iGPU (8 Chunks) tested on i5-4570 (HD4600) on CachyOS
*   dGPU (24 Chunks) tested on R9 8940HX (5060 Laptop=4060 desktop) on Windows 11
*   Choose a profile in shader settings that matches your hardware:

| Profile           |FPS (iGPU) |FPS (dGPU) |Description                  |
| ----------------- |---------- |---------- |---------------------------- |
| <strong>ULTRA_PERFORMANCE</strong> |190+       |440+       |Maximum FPS, minimal effects |
| <strong>PERFORMANCE</strong> |190+       |??         |Good balance for iGPU        |
| <strong>BALANCED</strong> |180+       |??         |A mix of features            |
| <strong>QUALITY</strong> |120+       |??         |More effects                 |
| <strong>ULTRA_QUALITY</strong> |120+       |350+       |Lowest FPS, All features     |

## Installation

1.  Install [Iris Shaders](https://irisshaders.dev/) or OptiFine
2.  Download Wispy Shaders
3.  Place the ZIP file in `.minecraft/shaderpacks/`
4.  Select Wispy in Video Settings → Shaders
5.  Choose a performance profile

## Optimizations

*   ~~Disabled~~ Deleted expensive composite passes by default
*   Fast gamma correction
*   Simplified post-processing
*   Optimized every composite pass and fog,lighting,sky,water,taa,bloom e.t.c
*   Reduced shader complexity
*   Too many to count now mainly faster math less calls,lookups and samples check [source](https://github.com/Epxlsol/Wispy-Shader) for more

[![Buy Me sum tea at https://ko-fi.com/M4M01S7TSM](https://storage.ko-fi.com/cdn/kofi6.png?v=4)](https://ko-fi.com/M4M01S7TSM)

## Links

*   Original Mellow: [https://www.curseforge.com/minecraft/shaders/mellow](https://www.curseforge.com/minecraft/shaders/mellow)
*   Report Issues: [https://github.com/epxlsol/wispy-shader/issues](https://github.com/epxlsol/wispy-shader/issues)

***

**Note**: This is a performance-focused fork. For the original experience with all features, use [Mellow Shaders](https://modrinth.com/shader/mellow).
