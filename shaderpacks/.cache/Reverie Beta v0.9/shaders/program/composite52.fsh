#include "/lib/all_the_libs.glsl"

#include "/generic/post/cas.fsh"
/* RENDERTARGETS:0 */
layout(location = 0) out vec4 Color;

in vec2 texcoord;

const bool colortex0MipmapEnabled = true;

void main() {
    Color = vec4(CAS(colortex0, texcoord, PIXELATION_AMOUNT, 0.2), 1);
}