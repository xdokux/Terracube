#version 330 compatibility
/* DRAWBUFFERS:0 */
// Writes the final combined (scene + bloom) result back to colortex0.

#include "lib/settings.glsl"

uniform sampler2D colortex0; // original scene
uniform sampler2D colortex1; // horizontally-blurred bright pass from composite1
uniform vec2 screenSize;

varying vec2 texCoord;

void main() {
    vec3 scene = texture2D(colortex0, texCoord).rgb;

#if BLOOM == 1
    vec2 texel = 1.0 / screenSize;
    float weights[9] = float[](0.028, 0.052, 0.083, 0.109, 0.125, 0.109, 0.083, 0.052, 0.028);

    vec3 bloom = vec3(0.0);
    for (int i = -4; i <= 4; i++) {
        bloom += texture2D(colortex1, texCoord + vec2(0.0, float(i) * texel.y * 2.0)).rgb * weights[i + 4];
    }

    scene += bloom * BLOOM_INTENSITY;
#endif

    gl_FragData[0] = vec4(scene, 1.0);
}
