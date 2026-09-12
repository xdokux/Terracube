#version 330 compatibility

#include "lib/settings.glsl"
#include "lib/common.glsl"

uniform sampler2D colortex0;
varying vec2 texCoord;

void main() {
    vec3 color = texture2D(colortex0, texCoord).rgb;
    color = posterize(color, float(POSTERIZE_LEVELS));
    gl_FragColor = vec4(color, 1.0);
}
