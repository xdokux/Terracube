# Baked Potato Shaders Changelog

## Version 8.0 — Aurora Debug Mode (Player Toggle)

- Restored **Aurora Debug Mode** as an optional Iris shader setting.
- Default remains **OFF**, preserving the existing rare natural Aurora event path exactly.
- **ON** bypasses only the rarity check and uses the existing Aurora renderer every true Overworld night.
- Restricted showcase mode to the established night palette interval so it never appears during day, sunrise, sunset, twilight, Nether, or End.
- Preserved existing Aurora colours, animation, brightness, gradients, weather response, rendering quality, and performance characteristics.
- Completed source, option-menu, compatibility, and archive-integrity verification.

## Version 7.9 — Optimization, Cleanup & Release Preparation

- Completed the official project rebrand to Baked Potato Shaders.
- Replaced all user-facing project names and release documentation.
- Rewrote the README for a professional Modrinth-ready release.
- Removed the obsolete Aurora debug setting and its compile-time test branch while preserving normal rare-event behaviour.
- Audited all shader stages, includes, uniforms, varyings, attributes, feature switches, and render-pass declarations.
- Verified that all include files and shader stages remain referenced and required.
- Retained internal identifiers and include paths where renaming would create unnecessary compatibility risk.
- Preserved rendering constants, visual calculations, user profiles, and exposed performance settings.
- Completed archive-integrity and source-consistency verification.

### Intentionally skipped

Potentially risky mathematical rewrites, precision reductions, shader-stage consolidation, and file deletion were deliberately skipped when visual equivalence could not be proven statically. Release stability and visual fidelity take priority over speculative micro-optimizations.
