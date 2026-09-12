const float DENSITY = 2.5;

const float CLOUD_EXTINCTION = 0.5;
const float CLOUD_SCATTERING = CLOUD_EXTINCTION;

// Multiple scattering approximation constants
const float a_BASE = 0.5; // attenuation 
const float b_BASE = 0.5; // contribution
const float c_BASE = 0.5; // eccentricity attenuation
const int MULTIPLE_SCATTERING_ORDERS = 4;

void intersect_with_cloud_plane_light(vec3 WorldPos, inout vec3 EndPos, vec3 RayDir) {
    if (RayDir.y > 0) {
        EndPos = intersectRayWithPlane(WorldPos, RayDir, CLOUD_UPPER_PLANE);
    }
    else {
        EndPos = intersectRayWithPlane(WorldPos, RayDir, CLOUD_LOWER_PLANE);
    }
}

float[MULTIPLE_SCATTERING_ORDERS] calc_mie_phase(float VdotL) {
    float[MULTIPLE_SCATTERING_ORDERS] MiePhase;
    float g = 1;
    float gBack = -1 * 0.6;

    for(int i = 0; i < MULTIPLE_SCATTERING_ORDERS; i++) {
        MiePhase[i] = hg_draine(VdotL, g);

        g *= c_BASE;
        gBack *= c_BASE;
    }
    
    return MiePhase;
}

struct LightData {
    float MiePhaseSun[MULTIPLE_SCATTERING_ORDERS], MiePhaseMoon[MULTIPLE_SCATTERING_ORDERS];
    bool MarchToSun, MarchToMoon;
};

float get_optical_depth_volumetric(vec3 LightPosN, vec3 WorldPosC, float Dither, int SampleCount) {
    float OpticalDepth = 0;
    vec3 EndPosL;
    intersect_with_cloud_plane_light(WorldPosC, EndPosL, view_player(LightPosN, false));
    float StepSizeL = min(24, length(EndPosL) / SampleCount);
    vec3 StepL = view_player(LightPosN, false) * StepSizeL;
    vec3 WorldPosCL = WorldPosC + StepL * Dither;
    for (int i = 1; i <= SampleCount; i++) {
        float DensityL = noise_clouds(WorldPosCL) * DENSITY;
        OpticalDepth += DensityL;

        WorldPosCL += StepL;
    }
    return OpticalDepth * StepSizeL * CLOUD_EXTINCTION;
}

float march_to_light_volumetric(vec3 LightPosN, vec3 WorldPosC, float Dither, float[MULTIPLE_SCATTERING_ORDERS] MiePhase) {
    float OpticalDepth = get_optical_depth_volumetric(LightPosN, WorldPosC, Dither, 4);
    float L = 0;
    float a = 1;
    float b = 1;

    for(int i = 0; i < MULTIPLE_SCATTERING_ORDERS; i++) {
        L += b * MiePhase[i] * exp(-a * OpticalDepth);

        a *= a_BASE;
        b *= b_BASE;
    }

    return L * CLOUD_SCATTERING;
}

vec4 get_clouds_volumetric(vec3 PlayerPos, vec3 PlayerPosN, const int STEP_COUNT, vec3 CameraPos, vec2 Dither, LightData Ld, float Depth, inout float DistToCloud) {
    vec3 StartPos, EndPos;
    bool Hit = intersect_with_cloud_plane(CameraPos, StartPos, EndPos, PlayerPosN, CLOUD_LOWER_PLANE, CLOUD_UPPER_PLANE);
    if (!Hit) return vec4(vec3(0), 1);

    // Calculate intersection with terrain
    float DistToCloudPlaneStart = len2(StartPos);
    if(Depth < 1) {
        float DistToTerrain = len2(PlayerPos);
        float DistToCloudPlaneEnd = len2(EndPos);
        if(DistToCloudPlaneStart > DistToTerrain) return vec4(vec3(0), 1);
        if(DistToCloudPlaneEnd > DistToTerrain) EndPos = PlayerPos;
    }

    float StepCount = adaptive_samples(STEP_COUNT, PlayerPosN.y);

    vec3 Step = (EndPos - StartPos) / StepCount;
    float StepSize = length(Step);
    float TotalTransmittance = 1;
    vec3 TotalScattering = vec3(0);

    vec3 PlayerPosC = StartPos + Dither.x * Step;

    for (int i = 1; i <= StepCount; i++) {
        vec3 WorldPosC = PlayerPosC + CameraPos;

        float Density = noise_clouds(WorldPosC);
        if (Density <= 1e-3) {
            PlayerPosC += Step;
            continue;
        }

        if(DistToCloud >= 1e6) DistToCloud = length(PlayerPosC);

        Density *= DENSITY;

        float Transmittance = exp(-Density * StepSize * CLOUD_EXTINCTION);
        
        float AmbientFactor = 0.3 + 0.7 * linstep(CLOUD_LOWER_PLANE, CLOUD_UPPER_PLANE, WorldPosC.y);
        vec3 Scattering = dataBuf.AmbientColor * ISOTROPIC_PHASE * 10 * AmbientFactor;

        if (Ld.MarchToSun) {
            Scattering += dataBuf.SunColorVlClouds * march_to_light_volumetric(sunPosN, WorldPosC, Dither.y, Ld.MiePhaseSun);
        }
        if (Ld.MarchToMoon) {
            Scattering += dataBuf.MoonColorVlClouds * march_to_light_volumetric(-sunPosN, WorldPosC, Dither.y, Ld.MiePhaseMoon);
        }

        if(lightningBoltPosition.w > 0) {
            float VdotLi = distance(lightningBoltPosition.xz, PlayerPosC.xz) * 0.07;
            Scattering += vec3(10) * ISOTROPIC_PHASE * exp(-VdotLi);
        }
        
        Scattering *= TotalTransmittance * (1 - Transmittance) / CLOUD_EXTINCTION;

        TotalScattering += Scattering;
        TotalTransmittance *= Transmittance;

        if(TotalTransmittance <= 1e-3) break;

        PlayerPosC += Step;
    }

    vec4 Final = vec4(TotalScattering, TotalTransmittance);
    return Final;
}

float get_optical_depth_flat(vec3 LightPosN, vec3 CloudPos, float Dither, int SampleCount) {
    float OpticalDepth = 0;
    float StepSizeL = 64;
    vec3 StepL = view_player(LightPosN, false) * StepSizeL;
    StepL.y = 0;
    vec3 CloudPosCL = CloudPos + StepL * Dither;
    for (int i = 1; i <= SampleCount; i++) {
        float DensityL = noise_clouds_flat(CloudPosCL);
        OpticalDepth += DensityL;

        CloudPosCL += StepL;
    }
    return OpticalDepth * StepSizeL * CLOUD_EXTINCTION;
}

float march_to_light_flat(vec3 LightPosN, vec3 CloudPos, float Dither, float[MULTIPLE_SCATTERING_ORDERS] MiePhase) {
    float OpticalDepth = get_optical_depth_flat(LightPosN, CloudPos, Dither, 4);
    float L = 0;
    float a = 1;
    float b = 1;

    for(int i = 0; i < MULTIPLE_SCATTERING_ORDERS; i++) {
        L += b * MiePhase[i] * exp(-a * OpticalDepth);

        a *= a_BASE;
        b *= b_BASE;
    }

    return L * CLOUD_SCATTERING;
}

vec4 get_clouds_flat(vec3 PlayerPos, vec3 PlayerPosN, vec3 CameraPos, vec2 Dither, LightData Ld, float Depth, inout float DistToCloud) {
    vec3 CloudPos = intersectRayWithPlane(CameraPos, PlayerPosN, 500);
    if (CloudPos == vec3(0)) return vec4(vec3(0), 1);
    if(Depth < 1) {
        float DistToTerrain = len2(PlayerPos);
        if(DistToTerrain < len2(CloudPos)) return vec4(vec3(0), 1);
    }
    CloudPos += CameraPos;

    float Density = noise_clouds_flat(CloudPos);
    if (Density <= 1e-5) {
        return vec4(0, 0, 0, 1);
    }
    DistToCloud = length(CloudPos);
    Density *= DENSITY;

    float Transmittance = exp(-Density * 50 * CLOUD_EXTINCTION);
    vec3 Scattering = dataBuf.AmbientColor * ISOTROPIC_PHASE * 5;

    if (Ld.MarchToSun) {
        Scattering += dataBuf.SunColorFlatClouds * march_to_light_flat(sunPosN, CloudPos, Dither.x, Ld.MiePhaseSun);
    }
    if (Ld.MarchToMoon) {
        Scattering += dataBuf.MoonColorFlatClouds * march_to_light_flat(-sunPosN, CloudPos, Dither.x, Ld.MiePhaseMoon);
    }

    Scattering *= (1 - Transmittance) / CLOUD_EXTINCTION;

    vec4 Final = vec4(Scattering, Transmittance);
    return Final;
}


vec4 get_clouds(vec3 PlayerPos, vec3 PlayerPosN, const int STEP_COUNT, vec3 CameraPos, const bool AnimateNoise, vec2 FragCoord, float Depth, inout float DistToCloud) {
    vec2 Dither = blue_noise(FragCoord, AnimateNoise).rg;
    
    float LHeight = sin(sunAngle * TAU);
    LightData Ld;
    Ld.MarchToSun = LHeight > -0.1;
    Ld.MarchToMoon = LHeight < 0.1;

    vec3 SunRay = view_player(sunPosN, false);
    if (Ld.MarchToSun) {
        float VdotL = dot(SunRay, PlayerPosN);
        Ld.MiePhaseSun = calc_mie_phase(VdotL);
    }
    if (Ld.MarchToMoon) {
        float VdotL = dot(-SunRay, PlayerPosN);
        Ld.MiePhaseMoon = calc_mie_phase(VdotL);
    }

    float _DistToCloudFlat = DistToCloud;
    vec4 CloudDataFlat = get_clouds_flat(PlayerPos, PlayerPosN, CameraPos, Dither, Ld, Depth, _DistToCloudFlat);

    float _DistToCloudVol = DistToCloud;
    vec4 CloudDataVol = get_clouds_volumetric(PlayerPos, PlayerPosN, STEP_COUNT, CameraPos, Dither, Ld, Depth, _DistToCloudVol);

    DistToCloud = min(_DistToCloudFlat, _DistToCloudVol); // Return dist to nearest cloud

    CloudDataFlat *= CloudDataVol.a;
    CloudDataFlat.rgb += CloudDataVol.rgb;

    float FogFactor = DistToCloud / 10000; 
    FogFactor = exp(-3 * FogFactor);
    return mix(vec4(0, 0, 0, 1), CloudDataFlat, FogFactor);
}