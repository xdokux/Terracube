#version 120

uniform sampler2D colortex5;
uniform sampler2D depthtex0;
uniform float viewWidth;
uniform float viewHeight;
uniform float far;
uniform float near;
varying vec2 texcoord;
uniform sampler2D colortex0;

#include "/lib/settings.glsl"
#include "/lib/colorgrading.glsl"

float edepth(vec2 coord) {
    return texture2D(colortex5, coord).x;
}
float luminance(vec3 color) {
    return dot(color, vec3(0.299, 0.587, 0.114));
}
float halftone(float radius, float spacing) {
    vec2 view = texcoord * vec2(viewWidth, viewHeight);
    float size = radius * 2 + spacing / 2;
    vec2 pos = mod(view, size);
    vec2 center = vec2(size * 0.5);
    return 1.0 - step(radius, length(pos - center));
}
vec3 celshade(vec3 clrr) {
    float dtresh = 1.0/(far-near)/(5000.0*Celradius);
    vec4 dc = vec4(edepth(texcoord.xy));

    vec3 border = vec3(1.0/viewWidth,1.0/viewHeight,0.0);
    vec4 sa = vec4(
    edepth(texcoord.xy + vec2(-border.x,-border.y)),
    edepth(texcoord.xy + vec2(border.x,-border.y)),
    edepth(texcoord.xy + vec2(-border.x,border.z)),
    edepth(texcoord.xy + vec2(border.z,border.y))
    );
    vec4 sb = vec4(
    edepth(texcoord.xy + vec2(border.x,border.y)),
    edepth(texcoord.xy + vec2(-border.x,border.y)),
    edepth(texcoord.xy + vec2(border.x,border.z)),
    edepth(texcoord.xy + vec2(border.z,-border.y))
    );

    vec4 dd = abs(2.0*dc - sa - sb) - dtresh;
    dd = step(dd.xyzw, vec4(0.0));
    float e = clamp(dot(dd, vec4(0.25)), 0.0, 1.0);
    return clrr * e;
}

void main() {
    vec4 finalColor = texture2D(colortex0, texcoord);
    vec3 color = finalColor.rgb;
    float ht = 1.0 - halftone(DotSize, DotSize*2);
    vec3 qrcolor = round(color * 16.0)/16.0;
    vec3 qfcolor = floor(color * 16.0)/16.0;
    float lum = luminance(color);
    float qlum = luminance(qfcolor);
    vec3 qcol1 = qfcolor;
    vec3 qcol2 = (lum - qlum > 0.03) ? qrcolor : qfcolor;
    finalColor.rgb = qcol1 * ht + qcol2 * (1.0 - ht);
    // 颜色
    #if COLORGRADING_EFFECT == 2
    finalColor = grayscale(finalColor);
    #elif COLORGRADING_EFFECT == 1
    finalColor = sepia(finalColor);
    #elif COLORGRADING_EFFECT == 0
    finalColor = wither(finalColor);
    #elif COLORGRADING_EFFECT == 3
    finalColor = CL8UDS(finalColor);
    #elif COLORGRADING_EFFECT == 4
    finalColor = QAQ(finalColor);
    #endif
    // 漫画描边
    #if CELSHADE == 1
    float depth = texture2D(depthtex0, texcoord).r;
    depth = (1.0 - far/near) * depth + (far / near);
    depth = 1.0 / depth;
    finalColor.rgb = celshade(finalColor.rgb);
    #endif

    gl_FragColor = finalColor;
}