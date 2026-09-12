vec3 blend_vl(vec3 OldColor, vec4 NewColor) {
    return OldColor * NewColor.a + NewColor.rgb;
}

vec4 get_clouds_flat(vec3 ViewPosN, vec3 PlayerPos, vec3 PlayerPosN, vec3 SunGlare) {
    vec2 CloudPos = PlayerPos.xz / (PlayerPos.y + length(PlayerPos.xz) / 6);

    const float ACTUAL_CLOUD_SPEED = CLOUD_SPEED / 100.;
    float Animation = float(frameTimeCounter) * ACTUAL_CLOUD_SPEED;
    CloudPos += cameraPosition.xz / 512;
    CloudPos = (CloudPos + Animation) * 32;

    float Noise = noise(CloudPos);
    float CloudAmount = CLOUD_AMOUNT / 100.0 + (rainStrength + thunderStrength) / 5;
    Noise *= smoothstep(0.0, 0.4 - CLOUD_OPACITY, Noise - 0.6 + CloudAmount);

    // Ultimate RTX raytraced ptgi 2000 cloud lighting
    const float DENSITY = 1.5;
    float Transmittance = exp(-Noise * DENSITY);
    float Absorbtion = noise(CloudPos + slpPlayerN.xz * 8);
    Absorbtion = Absorbtion * 1.5;

    vec3 CloudColorRaw = (SKY_GROUND * 2 + SunGlare);
    vec3 CloudColor = CloudColorRaw * 0.25 / PI;

    float VdotL = dot(ViewPosN, slpN);
    float MiePhase = max(xlf_phase(VdotL, 0.7) * 1.5, 1 / PI);
    CloudColor += SUN_DIRECT * MiePhase * exp(-Absorbtion * DENSITY);

    #ifdef IS_IRIS
        if(lightningBoltPosition.w > 0) {  
            CloudColor += vec3(1) * exp(-DENSITY * distance(lightningBoltPosition.xz / far, PlayerPosN.xz) * 4);
        }
    #endif

    return vec4(CloudColor * Noise * DENSITY, Transmittance);
}

vec4 get_clouds_wispy(vec3 ViewPosN, vec3 PlayerPos, vec3 PlayerPosN, vec3 SunGlare) {
    vec2 Wind = vec2(0.1, 0.05) * frameTimeCounter;
    float Displacement = texture(noisetex, (PlayerPos.xz / PlayerPos.y + Wind) * 0.01).r;
    float D = Displacement * noiseTextureResolution * 0.01;
    float Noise = texture(noisetex, (PlayerPos.xz / PlayerPos.y + D) / noiseTextureResolution * 10).b;
    Noise = pow(Noise, 6);
    Noise -= texture(noisetex, (PlayerPos.xz / PlayerPos.y - D * 0.5) / noiseTextureResolution * 80).g * 0.05;
    Noise = max(0, Noise);

    float Transmittance = exp(-Noise * 5 * 0.5);
    float VdotL = dot(ViewPosN, slpN);
    float MiePhase = max(xlf_phase(VdotL, 0.7), 1 / PI);
    vec3 Scattering = MiePhase * SUN_DIRECT + SKY_GROUND * 4 * ISOTROPIC_PHASE + SunGlare;
    Scattering *= (1 - Transmittance) / 0.5;

    return vec4(Scattering, Transmittance);
}

vec4 get_clouds_volumetric(vec3 ViewPosN, vec3 PlayerPos, vec3 PlayerPosN, vec3 SunGlare, float Dither) {
    const float PLANE_TOP = 1500.0;
    const float PLANE_BOTTOM = 1000.0;

    const float CLOUD_EXTINCTION = 0.5;
    const float CLOUD_SCATTERING = CLOUD_EXTINCTION;

    const int SAMPLE_COUNT = 12;
    int SampleCount = int(((1 - PlayerPosN.y) * 0.75 + 0.25) * SAMPLE_COUNT + 1);

    vec3 StartPos = PLANE_BOTTOM / PlayerPosN.y * PlayerPosN; 
    vec3 EndPos = PLANE_TOP / PlayerPosN.y * PlayerPosN;

    vec3 Step = (EndPos - StartPos) / SampleCount;
    float StepSize = length(Step);
    vec3 Pos = Step * Dither + StartPos + vec3(cameraPosition.x, 0, cameraPosition.z);

    vec3 Wind = frameTimeCounter * vec3(12, 0, 16) * CLOUD_SPEED;
    float CloudAmount = (CLOUD_AMOUNT - 12) / 10.0 + (rainStrength + thunderStrength * 0.5);
    
    float VdotL = dot(ViewPosN, slpN);
    float Phase = max(xlf_phase(VdotL, 0.7) * 1.5, 1 / PI);

    vec3 TotalScattering = vec3(0); float TotalTransmittance = 1;
    for(int i = 1; i <= SampleCount; i++) {
        float Base = texture(noisetex, (Pos.xz - Wind.xz) * 0.00007).r;

        float Alt = rescale(PLANE_BOTTOM, PLANE_TOP, Pos.y);
        float HeightDensity = linstep(0.0, 0.75, 1 - Alt) * linstep(0.0, 0.2, Alt);
        Base = pow(Base, 13 - CloudAmount * 5 + (1-HeightDensity) * 5);

        if(Base < 1e-4) {
            Pos += Step;
            continue;
        }

        float DetailTop = texture(colortex6, (Pos) / vec3(64) * 0.05).r;
        float DetailBottom = texture(colortex6, (Pos) / vec3(64) * 0.0125).r;
        Base = max(0, Base - DetailBottom * DetailTop * 0.1);

        float fms = CLOUD_SCATTERING * (1 - exp(-2.5 * Base * CLOUD_EXTINCTION)) / CLOUD_EXTINCTION;
        float MS = ISOTROPIC_PHASE * fms / (1 - fms);

        vec3 Scattering = (SKY_GROUND * 2 + SunGlare) * ISOTROPIC_PHASE;

        float LightFactor = linstep(PLANE_BOTTOM, PLANE_TOP, Pos.y) * 0.7 + 0.3;
        Scattering += SUN_DIRECT * (Phase + MS) * 1.5 * LightFactor;

        float Transmittance = exp(-Base * StepSize * CLOUD_EXTINCTION);
        Scattering *= CLOUD_SCATTERING * TotalTransmittance * (1 - Transmittance) / CLOUD_EXTINCTION;

        TotalScattering += Scattering;
        TotalTransmittance *= Transmittance;

        if(TotalTransmittance < 0.01) break;

        Pos += Step;
    }

    vec4 FinalColor = vec4(TotalScattering, TotalTransmittance);

    return FinalColor;
}


vec4 get_clouds_blocky_volumetric(vec3 ViewPosN, vec3 PlayerPos, vec3 PlayerPosN, vec3 SunGlare, float Dither, const bool IsSecondLayer) {
    float PLANE_TOP = !IsSecondLayer ? 110.0 : 510;
    float PLANE_BOTTOM = !IsSecondLayer ? 100.0 : 500;
    float CLOUD_SIZE = !IsSecondLayer ? 0.00025 : 0.0001;
    const float CLOUD_SCALE = 0.1; // Scale everything down to reduce precision loss

    const float CLOUD_EXTINCTION = 0.5;
    const float CLOUD_SCATTERING = CLOUD_EXTINCTION;

    const int SAMPLE_COUNT = 16;

    vec3 StartPos = PLANE_BOTTOM / PlayerPosN.y * PlayerPosN; 
    vec3 EndPos = PLANE_TOP / PlayerPosN.y * PlayerPosN; 
    vec3 Pos = StartPos + vec3(cameraPosition.x, 0, cameraPosition.z) * CLOUD_SCALE;

    float Wind = frameTimeCounter * 4 * CLOUD_SPEED * CLOUD_SCALE;
    Pos.x += Wind;
    Pos.z += IsSecondLayer ? 10000 : 0;

    float Density = texture(colortex3, Pos.xz * CLOUD_SIZE).a; // Sample right at the beginning
    vec2 TextureSize = textureSize(colortex3, 0);
    if(Density < 1e-2) { 
        // Travel to the edge of the next texel
        for(int i = 1; i < SAMPLE_COUNT; i++) {
            vec2 TexelPos = fract(Pos.xz * CLOUD_SIZE * TextureSize);
            vec2 DistToNext = ((step(0, PlayerPosN.xz)) - TexelPos) / PlayerPosN.xz / TextureSize;
            Pos += (PlayerPosN * min(DistToNext.x, DistToNext.y)) / CLOUD_SIZE;
            Pos += 0.005 * sign(vec3(PlayerPosN.x, 0, PlayerPosN.z)); // Bias to make sure we sample the correct texel
            
            if(Pos.y > PLANE_TOP) { // Break if we go too high
                break;
            }
            Density = texture(colortex3, Pos.xz * CLOUD_SIZE).a;
            
            if(Density > 1e-2) {
                break;
            }
        }
    }
    if(Density < 1e-2) return vec4(0,0,0,1);

    // Lighting

    // Same DDA, for the sun ray
    vec3 SunOffset = slpPlayerN;

    vec3 SunSamplePos = Pos;
    float SunT = 1;
    for(int i = 1; i <= 6; i++) {
        vec3 TexelPos;
        TexelPos.xz = fract(SunSamplePos.xz * CLOUD_SIZE * TextureSize);
        TexelPos.y = rescale(PLANE_BOTTOM, PLANE_TOP, SunSamplePos.y);
        vec3 DistToNext = ((step(0, SunOffset)) - TexelPos) / SunOffset / vec3(TextureSize.x, 1. / (PLANE_TOP - PLANE_BOTTOM), TextureSize.y);
        DistToNext.xz /= CLOUD_SIZE;
        float MinDist = min_component(DistToNext);
        SunSamplePos += SunOffset * MinDist;
        SunSamplePos += 0.001 * sign(SunOffset); // Bias to make sure we sample the correct texel

        float SunSample = texture(colortex3, SunSamplePos.xz * CLOUD_SIZE).a;
        SunT *= exp(-(MinDist * 0.3) * CLOUD_EXTINCTION); 
        if(SunT < 1e-4 || SunSamplePos.y > PLANE_TOP || SunSamplePos.y < PLANE_BOTTOM || SunSample < 1e-2) break;
    }

    float LightFactor = linstep(PLANE_BOTTOM, PLANE_TOP, Pos.y) * 0.7 + 0.3;
    vec3 Scattering = (SKY_GROUND + SunGlare) * LightFactor;

    float VdotL = dot(ViewPosN, slpN);
    float Phase = max(xlf_phase(VdotL, 0.7) * 1.5, 1 / PI);

    if(IsSecondLayer) SunT = mix(1.0, SunT, 0.5);
    Scattering += SUN_DIRECT * Phase * SunT;

    float Transmittance = exp(-Density * 2 * CLOUD_EXTINCTION);
    if(IsSecondLayer) Transmittance = mix(1.0, Transmittance, 0.25);
    Scattering *= CLOUD_SCATTERING * (1 - Transmittance) / CLOUD_EXTINCTION;


    vec4 FinalColor = vec4(Scattering, Transmittance);


    return FinalColor;
}


vec3 get_clouds(vec3 ViewPosN, vec3 PlayerPos, vec3 PlayerPosN, vec3 SunGlare, vec3 SkyColor, float Dither) {
    vec4 CloudColor; vec3 OgColor = SkyColor;

    #if (defined DOUBLE_CLOUD_LAYERS) && (CLOUD_STYLE != 0)
        #if CLOUD_STYLE == 1 || CLOUD_STYLE == 2
            CloudColor = get_clouds_wispy(ViewPosN, PlayerPos, PlayerPosN, SunGlare);
        #elif CLOUD_STYLE == 3
            CloudColor = get_clouds_blocky_volumetric(ViewPosN, PlayerPos, PlayerPosN, SunGlare, Dither, true);
        #endif
        SkyColor = blend_vl(SkyColor, CloudColor);
    #endif
    
    #if CLOUD_STYLE == 0
        return SkyColor;
    #elif CLOUD_STYLE == 1
        CloudColor = get_clouds_flat(ViewPosN, PlayerPos, PlayerPosN, SunGlare);
    #elif CLOUD_STYLE == 2
        CloudColor = get_clouds_volumetric(ViewPosN, PlayerPos, PlayerPosN, SunGlare, Dither);
    #elif CLOUD_STYLE == 3
        CloudColor = get_clouds_blocky_volumetric(ViewPosN, PlayerPos, PlayerPosN, SunGlare, Dither, false);
    #endif
    SkyColor = blend_vl(SkyColor, CloudColor);

    SkyColor = mix(OgColor, SkyColor, linstep(0, 0.2, PlayerPosN.y) * (CLOUD_OPACITY + 0.5));

    return SkyColor;
}
