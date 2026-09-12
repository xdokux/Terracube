#include "/lib/all_the_libs.glsl"
#include "/generic/post/taa.glsl"
in vec2 texcoord;

/* RENDERTARGETS:0,9 */
layout(location = 0) out vec4 Color;
layout(location = 1) out vec4 T2xData;

void main() {
    Color = texture(colortex0, texcoord);
    
    #ifndef DEBUG_DISABLE_TEMPORAL
    T2xData = RGBMEncode(Color.rgb);
    Color.rgb = T2x(Color.rgb, ivec2(gl_FragCoord.xy), texcoord);
    #endif
}
