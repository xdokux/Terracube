#version 460 compatibility
#include "/settings.glsl"

uniform sampler2D texture;

uniform float viewWidth;
uniform float viewHeight;

varying vec4 color;
varying vec2 coord0;

void main()
{
    vec2 txcoord = coord0;
    if (PIXELATION != 1){
        txcoord = txcoord * vec2(viewWidth / PIXELATION, viewHeight / PIXELATION);
        txcoord = floor(txcoord);
        txcoord = txcoord / vec2(viewWidth / PIXELATION, viewHeight / PIXELATION);
    }

    vec4 outcolor = texture2D(texture, txcoord);

    outcolor = floor(outcolor * 16);
    outcolor /= 16;

    if (SCALELINES != 1){
        float lines = fract((viewHeight / SCALELINES) * coord0.y) * 1.75;
        outcolor = outcolor * lines;
    }

    gl_FragData[0] = outcolor;
}
