/*
    composite1.fsh - bloom pass 1/2
    Extracts pixels above BLOOM_THRESHOLD, then blurs them
    horizontally only (separable blur: horizontal here, vertical in
    composite2.fsh). This is the real technique, not the "extra taps
    on the final image" trick used in the lighter Vanilla+ pack -
    worth it here since this pack targets high-end hardware.
*/
#version 330 compatibility
/* DRAWBUFFERS:1 */
// Writes to colortex1 only - colortex0 (the actual scene) is left
// untouched so composite2 can read both the original scene and this
// blurred bright-pass and combine them.

#include "lib/settings.glsl"
#include "lib/common.glsl"

uniform sampler2D colortex0;
uniform vec2 screenSize;

varying vec2 texCoord;

void main() {
    vec3 color = vec3(0.0);

#if BLOOM == 1
    vec2 texel = 1.0 / screenSize;
    float weights[9] = float[](0.028, 0.052, 0.083, 0.109, 0.125, 0.109, 0.083, 0.052, 0.028);

    for (int i = -4; i <= 4; i++) {
        vec3 c = texture2D(colortex0, texCoord + vec2(float(i) * texel.x * 2.0, 0.0)).rgb;
        float brightness = luminance(c);
        c *= smoothstep(BLOOM_THRESHOLD, BLOOM_THRESHOLD + 0.3, brightness);
        color += c * weights[i + 4];
    }
#endif

    gl_FragData[0] = vec4(color, 1.0);
}
