#version 120
/* 像素化 */
uniform sampler2D gColor;
varying vec2 texCoord;
#include "/lib/settings.glsl"

#if PIXEL == 0
const vec2 gridRes = vec2(160.0, 120.0);
#elif PIXEL == 1
const vec2 gridRes = vec2(320.0, 240.0);
#elif PIXEL == 2
const vec2 gridRes = vec2(640.0, 480.0);
#else PIXEL == 3
const vec2 gridRes = vec2(1280.0, 960.0);
#endif

void main() {
    vec2 pixelCoord = floor(texCoord * gridRes) / gridRes;
    vec3 color = texture2D(gColor, pixelCoord).rgb;

    gl_FragData[0] = vec4(color, 1.0);
}