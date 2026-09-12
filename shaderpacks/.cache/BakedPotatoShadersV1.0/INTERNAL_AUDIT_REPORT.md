# Baked Potato Shaders V8.0 — Internal Audit Report

## Scope

V8.0 restores the previously validated Aurora rarity-bypass control as an optional player-facing showcase mode. No Aurora colour, animation, brightness, geometry, weather response, sky blending, render pass, texture sampling, or non-Aurora rendering system was redesigned.

## Files intentionally modified

- `shaders/lib/overworld_aurora.glsl`
- `shaders/gbuffers_skybasic.fsh`
- `shaders/shaders.properties`
- `shaders/lang/en_us.lang`
- `README.md`
- `CHANGELOG.md`
- `INTERNAL_AUDIT_REPORT.md`

All other shader and resource files remain byte-identical to V7.9.

## Behaviour verification

### OFF — default

- `AURORA_DEBUG_MODE` defaults to `0`.
- The compiled event gate retains the existing `proceduralHash12` calculation and `step(0.9925, dayRandom)` rarity threshold.
- Existing night visibility, weather fade, horizon fade, upper fade, colours, animation, density, and final intensity remain unchanged.
- No additional runtime branch or calculation is present in the compiled OFF path because the option is resolved by the GLSL preprocessor.

### ON

- The rarity gate is replaced by a constant-time night interval check.
- The interval uses the same visible-sky transition time already calculated by `gbuffers_skybasic.fsh`.
- Aurora showcase mode is active only while `transitionTime >= 0.660 && transitionTime < 0.900`.
- This corresponds to the established true-night palette and excludes sunset, post-sunset twilight, pre-sunrise blue hour, sunrise, and daytime.
- Existing Overworld-only program structure inherently prevents the option from rendering in Nether or End.
- Existing weather behaviour remains unchanged because the original clear-weather fade and early return are untouched.

## Compatibility and structural audit

- Shader option declaration uses the established Iris syntax: `#define AURORA_DEBUG_MODE 0 // [0 1]`.
- The option is exposed in `screen.ATMOSPHERE` and has localized OFF/ON labels and description.
- Default value is OFF.
- No duplicate Aurora function, include, render pass, loop, texture sample, buffer, uniform, varying, or geometry path was added.
- Include paths, shader stages, preprocessor blocks, delimiters, and program pairs were checked.
- GLSL source remains `#version 120` compatible.

## Performance

- OFF: zero added runtime cost after preprocessing; the normal rare-event expression is unchanged.
- ON: cost is identical to a naturally active Aurora plus two scalar `step` operations used only instead of the rarity hash gate.
- No cost is added outside the existing Overworld sky fragment program.

## Runtime limitation

A live Minecraft/Iris session was unavailable in the build environment. Static preprocessing, timeline simulation, source-diff verification, and archive validation were completed. Final menu display and in-game night behaviour should be confirmed once on the target Iris installation before public upload.
