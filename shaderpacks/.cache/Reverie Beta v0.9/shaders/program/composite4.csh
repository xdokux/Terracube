#include "/lib/all_the_libs.glsl"
// Clouds & aerial perspective

#include "/generic/water.glsl"
#include "/generic/sky.glsl"
#include "/generic/clouds.glsl"
#include "/generic/shadow/main.glsl"
#include "/generic/shadow/vl.glsl"

#ifdef DIMENSION_OVERWORLD
const vec2 workGroupsRender = vec2(VOLUMETRICS_RES, VOLUMETRICS_RES);
#else
const vec2 workGroupsRender = vec2(0, 0);
#endif

mat2x3 aerial_prespective(vec3 EndPos, vec3 PlayerPosN, const int STEP_COUNT, vec2 FragPos, vec3 ScreenPos, bool IsDH) {
    vec3 WorldPos = cameraPosition;
    vec3 StartPos = vec3(0);
    if(!ray_intersect(WorldPos, StartPos, EndPos, PlayerPosN, CLOUD_UPPER_PLANE)) return mat2x3(vec3(0), vec3(1));

    float StepCount = adaptive_samples(STEP_COUNT, PlayerPosN.y);

    vec3 Step = (EndPos - StartPos) / StepCount;
    float StepSize = length(Step);
    vec3 TotalTransmittance = vec3(1);
    vec3 TotalScattering = vec3(0);
    float Dither = blue_noise(FragPos, true).r;
    vec3 PlayerPosC = StartPos + Step * Dither;

    float VdotL = dot(view_player(sLightPosN, false), PlayerPosN);

    float RayPhase = rayleigh_phase(VdotL);
    float MiePhase = cs_phase(VdotL, anisotropy);

    // Fog gets strong at morning
    float DaytimeFactor = worldTime > 12000 ? smoothstep(20000, 24000, worldTime) : 1 - smoothstep(0, 2000, worldTime);
    DaytimeFactor = max(DaytimeFactor, 0.33);
    float DensityConstant = DaytimeFactor * StepSize * 2500;

    float ShadowFallback = get_vl_shadowing(ScreenPos, sLightPosN, Dither, IsDH, true);

    for (int i = 1; i <= StepCount; i++) {
        vec3 EarthPosC = PlayerPosC + vec3(0, cameraPosition.y * 5, 0);
        vec3 WorldPosC = PlayerPosC + cameraPosition;

        float Len = length(EarthPosC);
        vec3 OpticalDepth = all_densities(Len) * StepSize * VL_OVERWORLD_STRENGTH;

        // Smoke-like ground fog
        float Density = pow4(1 - texture(worleyNoiseTexture, vec3(WorldPosC) / 64 / 6 + frameTimeCounter * 0.002).r);
        Density *= height_falloff(WorldPosC.y, 130);
        Density *= DensityConstant;
        Density *= 1 - smoothstep(farLod + 16, farLod + 32, length(PlayerPosC));
        OpticalDepth.y += Density;
        
        vec3 RayScattering = BETA_R * OpticalDepth.x;
        float MieScattering = BETA_M * OpticalDepth.y;

        vec3 MediumScattering = RayScattering + MieScattering;
        vec3 MediumExtinction = OpticalDepth.x * BETA_R_E + OpticalDepth.y * BETA_M_E;
        vec3 TransmittanceSample = exp(-MediumExtinction);

        vec3 ScatteringSample = calc_scatt_towards_sun(EarthPosC + vec3(0, EarthRad, 0), view_player(sLightPosN, false), Len, vec2(RayPhase, MiePhase), RayScattering, MieScattering) * get_shadowlight_color();

        vec3 ShadowNDCPosC = player_shadow(PlayerPosC);
        vec3 ShadowPosC = distort(ShadowNDCPosC);
        ShadowPosC = ShadowPosC * 0.5 + 0.5;
        float Shadowing = ShadowFallback;
        if(Shadowing > 0.01) 
            Shadowing *= get_shadow_unfiltered(PlayerPosC, ShadowPosC);

        #ifdef CLOUDS
            if(Shadowing > 0.01) {
                float _DistToCloud;
                float CloudShadow = get_clouds(vec3(1000), view_player(sLightPosN, false), 4, WorldPosC, false, vec2(0), 1, _DistToCloud).a;
                CloudShadow = mix(1-exp2(1-cloudCoverageVl), CloudShadow, linstep(0.2, 0.25, sin(sunAngle * TAU))); // No shadows in the morning because it looks weird
                Shadowing *= CloudShadow;
            }
        #endif

        float u = view_player(sunPosN, false).y * 0.5 + 0.5;
        float v = (EarthPosC.y) / (AtmRad - EarthRad);
        vec3 MS = texture(atm_multi_scattering_sampler, vec2(u, v)).rgb * MediumScattering;

        TotalScattering += TotalTransmittance * (ScatteringSample * Shadowing + MS * isOutdoorsSmooth) * (1 - TransmittanceSample) / MediumExtinction;


        // Don't try this at home
        // TotalScattering += TotalTransmittance * MediumScattering * (1 - TransmittanceSample) / MediumExtinction * dataBuf.AmbientColor;

        TotalTransmittance *= TransmittanceSample;

        PlayerPosC += Step;
    }

    return mat2x3(TotalScattering, TotalTransmittance);
}

layout(local_size_x = 16, local_size_y = 16) in;
void main() {
    const int VOLUMETRICS_RES_INV = int(1 / VOLUMETRICS_RES);
    #ifdef CLOUDS
        {
            vec2 FragPos = gl_GlobalInvocationID.xy * VOLUMETRICS_RES_INV + ivec2(frameCounter * VOLUMETRICS_RES, frameCounter) % VOLUMETRICS_RES_INV;
            vec2 texcoord = (FragPos + 0.5) * resolutionInv;
            bool IsDH;
            float Depth = max_depth_4x4(texcoord, IsDH);
            if(Depth > 0.56) {
                Positions Pos = get_positions(texcoord, Depth, IsDH, true);

                float _DepthCloud = 1e6;
                vec4 CloudData = get_clouds(Pos.Player, Pos.PlayerN, 32, cameraPosition, true, FragPos, Depth, _DepthCloud);

                if(_DepthCloud < 1e6) {
                    _DepthCloud = _DepthCloud / farLod / 4;
                }

                // _DepthCloud = reinhard(_DepthCloud);

                // Transmittance should default to 1
                CloudData.a = 1 - CloudData.a;
                imageStore(image0, ivec2(gl_GlobalInvocationID.xy), CloudData);
                imageStore(image1, ivec2(gl_GlobalInvocationID.xy), vec4(_DepthCloud, 0, 0, 0));
            } else {
                imageStore(image0, ivec2(gl_GlobalInvocationID.xy), vec4(0,0,0,0));
                imageStore(image1, ivec2(gl_GlobalInvocationID.xy), vec4(1e6, 0,0,0));
            }
        }
    #endif

    #if VL_OVERWORLD_MODE == 1
    if(isEyeInWater == 0) {
        bool IsDH;
        vec2 FragPos = (gl_GlobalInvocationID.xy + 0.5) * VOLUMETRICS_RES_INV;
        vec2 texcoord = FragPos * resolutionInv;
        float Depth = get_depth(texcoord, IsDH);
        if(Depth > 0.56) {
            Positions Pos = get_positions(texcoord, Depth, IsDH, true);
            
            mat2x3 AtmData = aerial_prespective(Pos.Player, Pos.PlayerN, VL_SAMPLES, FragPos, vec3(texcoord, Depth), IsDH);

            float T = dot(AtmData[1], vec3(0.33));
            T = 1 - T;
            
            imageStore(image2, ivec2(gl_GlobalInvocationID.xy), vec4(AtmData[0], T));
        } else {
            imageStore(image2, ivec2(gl_GlobalInvocationID.xy), vec4(0,0,0,0));
        }
    } else {
        imageStore(image2, ivec2(gl_GlobalInvocationID.xy), vec4(0,0,0,0));
    }
    #endif
}
