#define DEFERRED

#include "/lib/all_the_libs.glsl"

in vec2 texcoord;
flat in vec3 LightColorDirect; // This needs to be initialized in the vertex stage of the pass

#include "/generic/gtao.glsl"
#include "/generic/water.glsl"
#include "/generic/shadow/main.glsl"
#include "/generic/shadow/rsm.glsl"
#include "/generic/post/taa.glsl"


/* RENDERTARGETS:5,3 */
layout(location = 0) out vec4 BentNormalOut;
layout(location = 1) out vec4 GIDenoise;


void main() {
    bool IsDH;
    float Depth = get_depth(texcoord, IsDH);

    BentNormalOut = texture(colortex5, texcoord);
    if ((Depth > 0.56) && Depth < 1) {
        Positions Pos = get_positions(texcoord, Depth, IsDH, true);
        mat2x4 GbufferData = mat2x4(texture(colortex1, texcoord), texture(colortex2, texcoord));
        MaterialProperties Mat = unpack_material(GbufferData, IsDH);

        float Gtao = 1;
        vec3 BentNormal;
        #if AO_MODE == 2
            Gtao = gtao(Pos, IsDH, Mat.Normal, BentNormal);
        #endif

        BentNormalOut.zw = encodeUnitVector(view_player(BentNormal, IsDH)) * 0.5 + 0.5;

        vec3 Rsm = vec3(0);
        #ifdef RSM
            #ifndef DIMENSION_NETHER
                Rsm = rsm(Pos.Player, Mat.Normal, LightColorDirect);
            #endif
        #endif
        
        GIDenoise = vec4(Rsm.rgb, 1 - Gtao);
    }
    else {
        GIDenoise = vec4(0, 0, 0, 1);
    }
}