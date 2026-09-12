#version 120

#define final

#define SATURATION 1.0 // [0.0 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.0 1.05 1.10 1.15 1.20 1.25 1.30 1.35 1.40 1.45 1.50 1.55 1.60 1.65 1.70 1.75 1.80 1.85 1.90 1.95 2.0 3.0 100]

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex7;

varying vec2 texUV;

#include "/colourconversion.h"


void main() {
   vec4 color = texture2D(colortex0, texUV);
   vec4 info  = texture2D(colortex7, texUV);
   
   vec3 hsv = rgb2hsv(color.rgb);
   hsv.g *= SATURATION;
   color.rgb = hsv2rgb(hsv);
   
   vec4 t = texture2D(colortex1, texUV);

   gl_FragData[0] = color;
}
