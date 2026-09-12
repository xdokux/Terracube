# Dither3D Textures

**Note: This shader now uses a fully procedural implementation. No external texture files are required.**

## Previous Versions

Earlier versions of this shader required 3D texture files for the dither patterns. The current implementation generates all patterns procedurally using Bayer matrices in the shader code, eliminating the need for external texture files.

This provides several advantages:
- No texture file dependencies
- Smaller shader package size
- Easier to customize patterns via code
- Better performance on some GPUs

## Implementation Details

The procedural generation is handled in [lib/dither3d_core.glsl](../lib/dither3d_core.glsl):
- **Bayer patterns**: 4×4 Bayer matrix for dot positioning
- **Circular dots**: Generated using distance fields
- **Fractal layers**: Computed based on UV frequency analysis
- **Brightness curves**: Analytical functions replace ramp textures

If you need to reference the original texture-based approach, see the [Dither3D Unity project](https://github.com/runevision/Dither3D).
...
```

Note: OptiFine/Iris may require specific texture formats. Consult their documentation for supported 3D texture formats.
