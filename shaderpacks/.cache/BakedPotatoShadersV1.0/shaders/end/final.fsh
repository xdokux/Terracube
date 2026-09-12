#version 120

#include "/lib/settings.glsl"
#include "/lib/tonemap.glsl"

uniform sampler2D colortex1;
uniform sampler2D colortex2;

varying vec2 vTexCoord;

void main() {
    vec3 color = texture2D(colortex1, vTexCoord).rgb;
    color = finishColor(color);

    vec2 centered = vTexCoord * 2.0 - 1.0;
    float vignette = 1.0 - dot(centered, centered) * 0.035;
    color *= clamp(vignette, 0.90, 1.0);

    vec4 lineOverlay = texture2D(colortex2, vTexCoord);
    if (lineOverlay.a > 0.0) {
        color = mix(color, lineOverlay.rgb, lineOverlay.a);
    }

    gl_FragColor = vec4(color, 1.0);
}
