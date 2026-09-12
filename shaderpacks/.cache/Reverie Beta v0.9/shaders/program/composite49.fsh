#include "/lib/all_the_libs.glsl"
#include "/generic/post/taa.glsl"
in vec2 texcoord;

/* RENDERTARGETS:0,4,8 */
layout(location = 0) out vec4 Color;
layout(location = 1) out vec4 TAAData;
layout(location = 2) out vec4 PrevDepth;

void main() {
    Color = texture(colortex0, texcoord);

    #ifndef DEBUG_DISABLE_TEMPORAL
    TAAData.rgb = TAA(Color.rgb, ivec2(gl_FragCoord.xy), texcoord);
    Color.rgb = TAAData.rgb;
    TAAData = RGBMEncode(TAAData.rgb);
    #endif

    bool IsDH;
    PrevDepth = texture(colortex8, texcoord);
    PrevDepth.r = get_depth(texcoord, IsDH);

    #if AA_MODE == 1
        Color.rgb = pow(Color.rgb, vec3(1/2.2));
    #endif
}
