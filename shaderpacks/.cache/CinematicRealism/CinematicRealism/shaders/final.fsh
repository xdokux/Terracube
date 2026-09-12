#version 330 compatibility

#include "lib/settings.glsl"
#include "lib/common.glsl"

uniform sampler2D colortex0;
varying vec2 texCoord;

vec3 filmicTonemap(vec3 color) {
    vec3 x = max(vec3(0.0), color - 0.004);
    return (x * (6.2 * x + 0.5)) / (x * (6.2 * x + 1.7) + 0.06);
}

void main() {
    vec3 color = texture2D(colortex0, texCoord).rgb * EXPOSURE;
    vec3 tonemapped = mix(color, filmicTonemap(color), TONEMAP_STRENGTH);
    tonemapped = adjustSaturation(tonemapped, SATURATION);
    gl_FragColor = vec4(tonemapped, 1.0);
}
