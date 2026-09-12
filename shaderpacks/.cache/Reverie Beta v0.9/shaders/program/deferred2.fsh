#define DEFERRED

in vec2 texcoord;

flat in vec3 LightColorDirect;

#ifdef VOXY
/* RENDERTARGETS:0,5,1,2 */
layout(location = 2) out vec4 vxData1;
layout(location = 3) out vec4 vxData2;
#else
/* RENDERTARGETS:0,5 */
#endif
layout(location = 0) out vec4 Color;
layout(location = 1) out vec4 Shadow;


#include "/lib/all_the_libs.glsl"
#include "/generic/water.glsl"
#include "/generic/fog.glsl"
#include "/generic/shadow/main.glsl"
#include "/generic/shadow/rsm.glsl"
#include "/generic/lighting/lighting.fsh"
#include "/generic/sky.glsl"
#include "/generic/clouds.glsl"
#include "/generic/post/taa.glsl"
#include "/generic/shadow/vl.glsl"


void main() {
    bool IsDH;
    float Depth = get_depth(texcoord, IsDH);
    bool IsHand;
    Depth = correct_hand_depth(Depth, IsDH, IsHand);
    Positions Pos = get_positions(texcoord, Depth, IsDH, true);

    float Dither = dither(gl_FragCoord.xy, true);

    vec3 SkyColor = get_sky(Pos.ViewN, true, Pos.PlayerN.y); 
    if (Depth >= 1) {
        Color.rgb = SkyColor;
        
            if(dot(Pos.View, gbufferModelView[1].xyz) > 0) {
                #ifndef DIMENSION_NETHER
                    Color.rgb += get_stars(Pos.PlayerN);
                    Color.rgb += get_milky_way(Pos.PlayerN);
                    #ifdef AURORA
                        Color.rgb += get_aurora(Pos.PlayerN, Dither);
                    #endif
                #endif
            }
        
    }
    else {
        mat2x4 GbufferData = mat2x4(texture(colortex1, texcoord), texture(colortex2, texcoord));
        MaterialProperties Mat = unpack_material(GbufferData, IsDH);
        vec4 ArmorGlintData = texture(colortex10, texcoord);
        Mat.Albedo.rgb += ArmorGlintData.rgb;

        vec3 TerrainColor = calc_lighting(Pos, Mat, IsDH, texcoord, IsHand, Shadow);
        Color.rgb = mix(SkyColor, TerrainColor, Mat.chunkFade);
        
        #ifdef VOXY
            if(texture(depthtex1, texcoord).r >= 1) {
                vxData1 = texture(colortex17, texcoord);
                vxData2 = texture(colortex18, texcoord);
                vec4 vxTranslucent = texture(colortex16, texcoord);
                Color.rgb = mix(Color.rgb, vxTranslucent.rgb, vxTranslucent.a);
            } else {
                vxData1 = GbufferData[0];
                vxData2 = GbufferData[1];
            }
        #endif
    }

    
}
