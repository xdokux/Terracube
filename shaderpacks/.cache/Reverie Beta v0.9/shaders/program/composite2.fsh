#include "/lib/all_the_libs.glsl"

in vec2 texcoord;
flat in vec3 LightColorDirect; // This needs to be initialized in the vertex stage of the pass

#include "/generic/water.glsl"
#include "/generic/shadow/main.glsl"

#include "/generic/sky.glsl"
#include "/generic/shadow/vl.glsl"
#include "/generic/fog.glsl"
#include "/generic/clouds.glsl"
#include "/generic/reflections.glsl"
#include "/generic/post/taa.glsl"


/* RENDERTARGETS:0 */
layout(location = 0) out vec4 Color;


// Taken from spectrum: https://github.com/zombye/spectrum
vec3 refract2(vec3 I, vec3 N, vec3 NF, float eta) {
    float NoI = dot(N, I);
    float k = 1.0 - eta * eta * (1.0 - NoI * NoI);
    if (k < 0.0) {
        return vec3(0.0);
    } else {
        float sqrtk = sqrt(k);
        vec3 R = (eta * dot(NF, I) + sqrtk) * NF - (eta * NoI + sqrtk) * N;
        return normalize(R * sqrt(abs(NoI)) + eta * I);
    }
}

void main() {
    bool IsDH;
    float Depth = get_depth(texcoord, IsDH);
    Positions Pos = get_positions(texcoord, Depth, IsDH, true);
    bool IsHand;
    Depth = correct_hand_depth(Depth, IsDH, IsHand);

    float Dither = dither(gl_FragCoord.xy, true);

    if (Depth < 1) {
        mat2x4 GbufferData = mat2x4(texture(colortex1, texcoord), texture(colortex2, texcoord));
        MaterialProperties Mat = unpack_material(GbufferData, IsDH);
        if(Mat.Id == MATERIAL_WATER) {
            Mat.Normal = view_player(Mat.Normal, IsDH);
            mat3 TBN = tbn_normal(Mat.Normal);
            vec3 WaterPos = get_water_parallax(Pos.World, Pos.PlayerN);
            Mat.Normal = TBN * get_water_normal(WaterPos, Mat.Normal);
            Mat.Normal = player_view(Mat.Normal, IsDH);
        }

        bool IsDH1;
        float Depth1 = get_depth_solid(texcoord, IsDH1);
        vec3 ViewPos1 = screen_view(vec3(Pos.Screen.xy, Depth1), IsDH1, true);
        if (Depth != Depth1 && Depth1 < 1) {
            vec3 RefractedDir = refract2(Pos.ViewN, Mat.Normal, Mat.FlatNormal, 0.7518);

            vec3 RefractedPos = ViewPos1 + RefractedDir * distance(Pos.View, ViewPos1);
            vec3 ScreenPosRef = view_screen(RefractedPos, IsDH1, true);

            vec4 NewDepths;
            if(IsDH1) {
                NewDepths = textureGather(dhDepthTex1, ScreenPosRef.xy, 0);
            } else {
                NewDepths = textureGather(depthtex1, ScreenPosRef.xy, 0);
            }
            float NewDepthClosest = min_component(NewDepths);
            if (NewDepthClosest < Depth)
                ScreenPosRef = Pos.Screen;
            else {
                Depth1 = lerp(NewDepths.x, NewDepths.y, NewDepths.z, NewDepths.w, ScreenPosRef.xy);
                ViewPos1 = screen_view(vec3(Pos.Screen.xy, Depth1), IsDH1, true);
            }

            Color = texture(colortex0, ScreenPosRef.xy);
        }
        else {
            Color = texture(colortex0, Pos.Screen.xy);
        }

        if (Mat.Id == MATERIAL_WATER && isEyeInWater == 0) {
            vec3 PlayerPos1 = view_player(ViewPos1, IsDH);
            mat2x3 VlResult = do_water_vl(Pos.Player, PlayerPos1, Pos.PlayerN, Dither, LightColorDirect, vec3(Pos.Screen.xy, Depth1), IsDH1, 4, VL_WATER_RT);
            Color.rgb = mix(Color.rgb, blend_vl(Color.rgb, VlResult), Mat.chunkFade);
        }

        bool IsMetal, IsHardcodedMetal;
        mat2x3 Reflectance = get_reflectance(Mat.F0, Mat.Id, Mat.Albedo, IsMetal, IsHardcodedMetal);
        float Smoothness = get_smoothness(Mat.Smoothness, Mat.Id);
        // Reflections
        if (Smoothness > 0.3 && isEyeInWater == 0) {
            #ifdef ROUGH_REFLECTIONS
            bool RoughReflections = Smoothness < 0.95 && Mat.Id != MATERIAL_WATER;
            #else 
            bool RoughReflections = false;
            #endif

            float RayCount = RoughReflections ? ROUGH_REFLECTIONS_STEPS : 1;
            vec2 Noise = blue_noise(gl_FragCoord.xy, true).rg;
            float Roughness = smoothness_to_roughness(Smoothness);
            mat3 TBN = tbn_normal(Mat.Normal);
            for(int i = 1; i <= RayCount; i++) {
                vec3 RefNormal;
                if(RoughReflections) {
                    float OffsetAng = (i + Noise.x) * TAU / RayCount;
                    vec2 Offset = Noise.y * vec2(cos(OffsetAng), sin(OffsetAng));
                    
                    RefNormal = TBN * SampleVndf_GGX(Offset * 0.5 + 0.5, -(TBN * Pos.ViewN), vec2(Roughness));
                } else {
                    RefNormal = Mat.Normal;
                }
            
                vec3 ReflectionBlendFactor = vec3(Smoothness / RayCount);

                if (IsHardcodedMetal) {
                    ReflectionBlendFactor *= fresnel_metals(RefNormal, -Pos.ViewN, Reflectance);
                } else {
                    ReflectionBlendFactor *= schlick(RefNormal, -Pos.ViewN, Reflectance[0]);
                }

                if(IsMetal) {
                    ReflectionBlendFactor *= Mat.Albedo;
                }
                
                Color.rgb += ssr(RefNormal, Pos, IsDH, Mat.Lightmap.y, Dither) * ReflectionBlendFactor * Mat.chunkFade;
            }
        }

        // Specular
        float Shadow = texture(colortex5, Pos.Screen.xy).r;
        float NdotL = max(dot(sLightPosN, Mat.Normal), 0);
        Shadow *= NdotL;
        if (Shadow != 0) {
            vec3 H = normalize(sLightPosN - Pos.ViewN); // Half-way vector
            vec3 F;
            if (IsHardcodedMetal) {
                F = fresnel_metals(H, -Pos.ViewN, Reflectance);
            }
            else {
                F = schlick(H, -Pos.ViewN, Reflectance[0]);
            }

            vec3 Specular = cook_torrance(-Pos.ViewN, sLightPosN, Mat.Normal, 1 - Smoothness, H, F);

            if(IsMetal) {
                Specular *= Mat.Albedo;
            }

            if(isEyeInWater == 1) {
                Specular *= WaterColor;
            }
            
            Color.rgb += Specular * LightColorDirect * Shadow * Mat.chunkFade;
        }
    }
    else {
        Color = texture(colortex0, texcoord);
    }
}
