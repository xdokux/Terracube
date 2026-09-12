/*
    final.fsh
    ---------------------------------------------------------------
    Pipeline stage: FINAL (last stage before the screen)
    Reads: colortex0 (fully composited scene)
    Writes: the actual screen framebuffer

    One tonemap curve + one saturation lerp. Both are single cheap
    per-pixel math operations with zero texture fetches beyond the
    one read of colortex0 - negligible cost on any hardware,
    including the UHD 630, so this stays identical across profiles.
    ---------------------------------------------------------------
*/
#version 330 compatibility

#include "lib/settings.glsl"
#include "lib/common.glsl"

uniform sampler2D colortex0;
varying vec2 texCoord;

// Cheap filmic-ish curve (a simplified ACES-style approximation) -
// rolls off highlights instead of hard-clipping them, and lifts
// shadows very slightly. Not the full ACES matrix pipeline (that
// needs 3x3 color-space transforms we don't need for this look).
vec3 filmicTonemap(vec3 color) {
    vec3 x = max(vec3(0.0), color - 0.004);
    return (x * (6.2 * x + 0.5)) / (x * (6.2 * x + 1.7) + 0.06);
}

void main() {
    vec3 color = texture2D(colortex0, texCoord).rgb;

    vec3 tonemapped = mix(color, filmicTonemap(color), TONEMAP_STRENGTH);
    tonemapped = adjustSaturation(tonemapped, SATURATION);

    gl_FragColor = vec4(tonemapped, 1.0);
}
