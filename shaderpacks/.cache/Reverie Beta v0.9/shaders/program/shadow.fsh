#include "/lib/all_the_libs.glsl"
#include "/generic/water.glsl"
in vec2 texcoord;
in vec4 glcolor;

flat in vec3 Normal;
flat in float Material;

in vec3 PlayerPos;

#ifdef RSM
    /* RENDERTARGETS:0,2,1 */
#else
    /* RENDERTARGETS:0,2 */
#endif
layout(location = 0) out vec4 Color;
layout(location = 1) out vec4 MaterialBuf;
#ifdef RSM
    layout(location = 2) out vec4 ShadowNormal;
#endif

void main() {
    Color = texture(gtexture, texcoord) * glcolor;
    if (Color.a < 0.1) {
        discard;
        return;
    }

    if (renderStage == MC_RENDER_STAGE_ENTITIES) { // Stop entities from contributing to RSM because it ruins temporal stability
        Color.rgb = vec3(0);
    } 

    Color.rgb = srgb_linear(Color.rgb);

    #ifdef RSM
        ShadowNormal.rg = encodeUnitVector(Normal) * 0.5 + 0.5;
    #endif
    MaterialBuf.r = 0;
}
