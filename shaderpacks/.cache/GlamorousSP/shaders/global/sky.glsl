float fogify(float x, float w) {
    return w / (x * x + w);
}

vec3 round_sun(float Dist) {
    Dist = Dist * 0.5 + 0.5;
    const vec3 SUN_COLOR = vec3(5, 3.5, 0.8);
    const vec3 MOON_COLOR = vec3(1, 1.5, 2.5);
    float What = sunriseStrength + sunsetStrength;
    vec3 Color = SUN_COLOR * (1 - smoothstep(0., 0.0015, 1 - Dist)) * (dayStrength + What);
    Color += MOON_COLOR * (smoothstep(0.9995, 1., 1 - Dist)) * (nightStrength + What);
    Color *= 1 - rainStrength;
    return Color;
}

vec3 get_sun_glare(float Dist) {
    const vec3 SUN_GLARE = to_linear(vec3(f_SUN_GLARE_R, f_SUN_GLARE_G, f_SUN_GLARE_B));

    float DarkenFactor = 1 - rainStrength * RAIN_SKY_DARKENING;
    #ifdef IS_IRIS
        DarkenFactor *= 1 - thunderStrength * 0.75;
    #endif

    vec3 SunGlare = SUN_GLARE * DarkenFactor;
    float Visibility = sunsetStrength + sunriseStrength;
    Visibility = pow2(Visibility);

    return SunGlare * (Dist * 0.5 + 0.5) * Visibility;
}

// GlamorousSP custom sky palette
// Stronger identity pass: deeper day sky, purple/pink/gold sunsets, and warmer clouds.
vec3 glamorous_sky_top() {
    vec3 NoonTop    = to_linear(vec3(0.045, 0.28, 0.86));
    vec3 SunriseTop = to_linear(vec3(0.28, 0.20, 0.55));
    vec3 SunsetTop  = to_linear(vec3(0.20, 0.12, 0.42));
    vec3 NightTop   = to_linear(vec3(0.004, 0.012, 0.050));

    return SunriseTop * sunriseStrength + NoonTop * dayStrength + SunsetTop * sunsetStrength + NightTop * nightStrength;
}

vec3 glamorous_sky_ground() {
    vec3 NoonGround    = to_linear(vec3(0.42, 0.70, 1.05));
    vec3 SunriseGround = to_linear(vec3(1.00, 0.62, 0.32));
    vec3 SunsetGround  = to_linear(vec3(1.00, 0.48, 0.34));
    vec3 NightGround   = to_linear(vec3(0.018, 0.030, 0.088));

    return SunriseGround * sunriseStrength + NoonGround * dayStrength + SunsetGround * sunsetStrength + NightGround * nightStrength;
}

vec3 glamorous_twilight_color() {
    vec3 SunriseGold = to_linear(vec3(1.15, 0.66, 0.24));
    vec3 SunsetPink  = to_linear(vec3(1.00, 0.38, 0.52));
    return SunriseGold * sunriseStrength + SunsetPink * sunsetStrength;
}

vec3 glamorous_cloud_base() {
    float Twilight = sunriseStrength + sunsetStrength;
    vec3 Base = mix(SKY_GROUND, glamorous_sky_ground(), 0.90);
    Base += glamorous_twilight_color() * Twilight * 0.40;
    return Base;
}

vec3 get_clouds_flat(vec3 ViewPosN, vec3 PlayerPos, vec3 PlayerPosN, vec3 SunGlare, vec3 SkyColor) {
    vec2 CloudPos = PlayerPos.xz / (PlayerPos.y + length(PlayerPos.xz) / 6);

    const float ACTUAL_CLOUD_SPEED = CLOUD_SPEED / 100.;
    float Animation = float(frameTimeCounter) * ACTUAL_CLOUD_SPEED;
    CloudPos += cameraPosition.xz / 512;
    CloudPos = (CloudPos + Animation) * 32;

    float CloudAmount = CLOUD_AMOUNT / 100.0 + (rainStrength + thunderStrength) / 10;

    // GlamorousSP soft vanilla clouds:
    // Quantized low-frequency cloud coverage gives the vanilla block-cloud feel,
    // while a stronger smooth pass keeps them from looking pixelated/fake.
    vec2 BlockSamplePos = floor(CloudPos * 0.34) / 0.34;
    float BlockCoverage = fbm_clouds(BlockSamplePos * 0.46, 3);
    float SoftCoverage = fbm_clouds(CloudPos * 0.14, 2);
    float EdgeBreakup = fbm_clouds(CloudPos * 0.62, 2) * 0.08;

    float CloudMask = BlockCoverage * 0.58 + SoftCoverage * 0.42 + EdgeBreakup;
    float Threshold = 0.50 - CloudAmount * 0.82;
    float EdgeSoftness = 0.075 + CLOUD_OPACITY * 0.12;

    float Noise = smoothstep(Threshold, Threshold + EdgeSoftness, CloudMask);
    Noise = pow(Noise, 0.62);
    Noise *= smoothstep(0.0, 0.2, PlayerPosN.y);

    const float DENSITY = 1.46;
    float Transmittance = exp(-Noise * DENSITY);
    float Absorbtion = fbm_clouds(CloudPos * 0.16 + view_player(sunOrMoonPosN, false).xz * 4, 2);
    Absorbtion = pow2(Absorbtion * 1.35);

    vec3 CloudColorRaw = (glamorous_cloud_base() * 2.10 + SunGlare * 1.10);
    vec3 CloudColor = CloudColorRaw * 0.26 / PI;

    float VdotL = dot(ViewPosN, sunOrMoonPosN);
    float MiePhase = max(xlf_phase(VdotL, 0.66) * 1.25, 1 / PI);
    float Twilight = sunriseStrength + sunsetStrength;

    CloudColor += SUN_DIRECT * MiePhase * exp(-Absorbtion * DENSITY);
    CloudColor += glamorous_twilight_color() * Twilight * (MiePhase * 0.55 + 0.10) * exp(-Absorbtion * DENSITY);

    // Slight underside softness so the clouds look like vanilla clouds with shader lighting,
    // not the old wispy Mellow layer.
    CloudColor *= 0.82 + 0.18 * smoothstep(0.0, 0.35, PlayerPosN.y);

    #ifdef IS_IRIS
        if(lightningBoltPosition.w > 0) {  
            CloudColor += vec3(1) * exp(-DENSITY * distance(lightningBoltPosition.xz / far, PlayerPosN.xz) * 4);
        }
    #endif

    return SkyColor * Transmittance + CloudColor * Noise * DENSITY;
}

vec3 get_clouds_volumetric(vec3 ViewPosN, vec3 PlayerPos, vec3 PlayerPosN, vec3 SunGlare, vec3 SkyColor, float Dither) {
    const float PLANE_TOP = 1500.0;
    const float PLANE_BOTTOM = 1000.0;

    const float CLOUD_EXTINCTION = 0.5;
    const float CLOUD_SCATTERING = CLOUD_EXTINCTION;

    const int SAMPLE_COUNT = 6;

    vec3 StartPos = PLANE_BOTTOM / PlayerPosN.y * PlayerPosN; 
    vec3 EndPos = PLANE_TOP / PlayerPosN.y * PlayerPosN;

    vec3 Step = (EndPos - StartPos) / SAMPLE_COUNT;
    float StepSize = length(Step);
    vec3 Pos = Step * Dither + StartPos + vec3(cameraPosition.x, 0, cameraPosition.z);

    vec3 Wind = frameTimeCounter * vec3(12, 0, 16) * CLOUD_SPEED;
    Pos.xz -= Wind.xz;

    float Phase = max(1 / PI, xlf_phase(dot(sunOrMoonPosN, ViewPosN), 0.65));
    float Twilight = sunriseStrength + sunsetStrength;

    vec3 TotalScattering = vec3(0); float TotalTransmittance = 1;
    for(int i = 1; i <= SAMPLE_COUNT; i++) {
        float Base = texture(noisetex, Pos.xz * 0.00005).r;

        float CloudAmount = (CLOUD_AMOUNT - 12) / 100.0 + (rainStrength + thunderStrength * 0.5);
        // Base *= smoothstep(0.0, 0.4 - CLOUD_OPACITY, Base - 0.55 + CloudAmount);
        // Base = pow(Base, 8 - CloudAmount) * 3;

        float Alt = rescale(PLANE_BOTTOM, PLANE_TOP, Pos.y);
        float HeightDensity = linstep(0.0, 0.75, 1 - Alt) * linstep(0.0, 0.2, Alt);
        Base = pow(Base, 5 - CloudAmount * 2 + (1-HeightDensity) * 3) * 2;
        float Density = Base * (1-linstep(Base - 0.1, 1.0, Alt)) * linstep(0.0, 0.2, Alt);

        if(Base < 1e-2) {
            Pos += Step;
            continue;
        }

        float DetailTop = 1-texture(colortex6, (Wind + Pos) / vec3(256, 32, 256) * 0.1).r * 0.75;
        float DetailBottom = texture(colortex6, (Wind + Pos) / vec3(256, 32, 256) * 0.025).r;
        Base = max(0, Base - DetailBottom * DetailTop * 0.25);

        float fms = CLOUD_SCATTERING * (1 - exp(-1.5 * Base * CLOUD_EXTINCTION)) / CLOUD_EXTINCTION;
        float MS = ISOTROPIC_PHASE * fms / (1 - fms);

        vec3 Scattering = (glamorous_cloud_base() * 2.25 + SunGlare * 1.20) * ISOTROPIC_PHASE;

        float LightFactor = linstep(PLANE_BOTTOM, PLANE_TOP, Pos.y) * 0.7 + 0.3;
        Scattering += SUN_DIRECT * (Phase + MS) * 2 * LightFactor;
        Scattering += glamorous_twilight_color() * Twilight * (Phase + MS + 0.18) * LightFactor * 1.25;

        float Transmittance = exp(-Base * StepSize * CLOUD_EXTINCTION);
        Scattering *= CLOUD_SCATTERING * TotalTransmittance * (1 - Transmittance) / CLOUD_EXTINCTION;

        TotalScattering += Scattering;
        TotalTransmittance *= Transmittance;

        if(TotalTransmittance < 0.01) break;

        Pos += Step;
    }

    TotalTransmittance = mix(1, TotalTransmittance, linstep(0, 0.3, PlayerPosN.y) * (CLOUD_OPACITY + 0.5));

    return mix(TotalScattering, SkyColor, TotalTransmittance);
}

vec3 get_clouds(vec3 ViewPosN, vec3 PlayerPos, vec3 PlayerPosN, vec3 SunGlare, vec3 SkyColor, float Dither) {
    #if CLOUD_STYLE == 0
        return SkyColor;
    #elif CLOUD_STYLE == 1
        return get_clouds_flat(ViewPosN, PlayerPos, PlayerPosN, SunGlare, SkyColor);
    #elif CLOUD_STYLE == 2
        // GlamorousSP uses the same soft-vanilla cloud layer for high profiles too.
        return get_clouds_flat(ViewPosN, PlayerPos, PlayerPosN, SunGlare, SkyColor);
    #endif
}

vec3 get_sky(vec3 ViewPosN, vec3 SunGlare) {
    float rawUpDot = dot(ViewPosN, gbufferModelView[1].xyz);
    float upDot = rawUpDot + 0.1; //not much, what's up with you?

    float Horizon = fogify(max(upDot, 0.0), 0.040);
    float UpperSky = smoothstep(0.10, 0.95, upDot);
    float Twilight = (sunriseStrength + sunsetStrength) * (1.0 - rainStrength);
    float HorizonBand = pow2(1.0 - smoothstep(0.0, 0.62, abs(upDot)));

    vec3 BaseColor = mix(SKY_TOP, SKY_GROUND + SunGlare, Horizon);

    vec3 GlamTop = glamorous_sky_top();
    vec3 GlamGround = glamorous_sky_ground();
    vec3 GlamColor = mix(GlamTop, GlamGround + SunGlare * 1.65, Horizon);

    vec3 SunsetPink = to_linear(vec3(1.00, 0.34, 0.48));
    vec3 GoldOrange = to_linear(vec3(1.05, 0.58, 0.22));
    vec3 PurpleTop  = to_linear(vec3(0.22, 0.13, 0.46));

    float sunDot = clamp(dot(ViewPosN, sunOrMoonPosN) * 0.5 + 0.5, 0.0, 1.0);
    float SunGlow = pow(sunDot, 12.0) * Twilight;

    // More obvious GlamorousSP sunset: purple above, pink/orange near the horizon.
    GlamColor = mix(GlamColor, PurpleTop, Twilight * UpperSky * 0.20);
    GlamColor += SunsetPink * sunsetStrength * HorizonBand * 0.32;
    GlamColor += GoldOrange * (sunriseStrength + sunsetStrength * 0.35) * HorizonBand * 0.36;
    GlamColor += (GoldOrange * 0.75 + SunsetPink * 0.25) * SunGlow * 0.42;

    // Cleaner blue daytime and darker blue night.
    GlamColor += to_linear(vec3(0.00, 0.05, 0.16)) * dayStrength * UpperSky * 0.12;
    GlamColor += to_linear(vec3(0.015, 0.035, 0.13)) * nightStrength * (1.0 - Horizon) * 1.45;

    // Rain keeps it from becoming neon during bad weather.
    GlamColor *= 1.0 - rainStrength * 0.45;

    return mix(BaseColor, GlamColor, 0.88);
}

float get_stars(vec3 PlayerPos) {
    vec3 StarCoord = PlayerPos / (PlayerPos.y + length(PlayerPos.xz));
    StarCoord.x += frameTimeCounter * 0.001;
    const float ACTUAL_STAR_SIZE = STAR_SIZE * 512;
    StarCoord = floor(StarCoord * ACTUAL_STAR_SIZE) / ACTUAL_STAR_SIZE;

    float Visibility = smoothstep(0.0, 0.1, StarCoord.y); // Smoothly fade out stars near the bottom of the sky
    #ifdef DIMENSION_OVERWORLD
    Visibility *= nightStrength;
    #endif
    return max(0, random(StarCoord.xz) - 0.996) * 50 * Visibility * STAR_STRENGTH;
}

vec3 get_aurora(vec3 PlayerPosN, float Dither) {
    float AuroraStrength = AURORA_STRENGTH * nightStrength;
    #ifndef AURORA_EVERYWHERE
        if(precipitationSmooth <= 1.01) return vec3(0);
        AuroraStrength *= precipitationSmooth - 1;
    #endif
    
    const vec3 COLOR_TOP = pow(vec3(28, 255, 218) / 255.0, vec3(2.2));
    const vec3 COLOR_BOTTOM = pow(vec3(122, 255, 28) / 255.0, vec3(2.2));

    // Calculate intersection with aurora plane
    const float PLANE_TOP = 10.0 + AURORA_HEIGHT;
    const float PLANE_BOTTOM = 10.0;

    vec3 StartPos = PLANE_BOTTOM / PlayerPosN.y * PlayerPosN; 
    vec3 EndPos = PLANE_TOP / PlayerPosN.y * PlayerPosN;

    const int SAMPLE_COUNT = 2;

    vec3 Step = (EndPos - StartPos) / SAMPLE_COUNT;
    vec3 Pos = Step * Dither + StartPos;

    vec2 Wind = frameTimeCounter * vec2(0.25, 0.33);

    vec3 AuroraColor = vec3(0);
    for(int i = 1; i <= SAMPLE_COUNT; i++) {
        float Noise = texture(noisetex, (Pos.xz - Wind) / vec2(100, 200)).r;

        Noise = pow2(pow4(Noise));
        Noise *= smoothstep(0.0, 0.2, PlayerPosN.y);
        AuroraColor += Noise * mix(COLOR_BOTTOM, COLOR_TOP, smoothstep(0, 1, Dither));

        Pos += Step;
    }

    return AuroraColor * AuroraStrength / SAMPLE_COUNT;
}


vec3 get_end_saturn_rings(vec3 PlayerPosN) {
    // GlamorousSP End rings: tilted Saturn-like dust bands replacing the End aurora.
    vec3 RingNormal = normalize(vec3(0.18, 0.92, -0.35));
    vec3 RingAlong  = normalize(vec3(0.96, -0.05, 0.28));

    float PlaneDist = abs(dot(PlayerPosN, RingNormal));
    float Along = dot(PlayerPosN, RingAlong);

    float WideBand = smoothstep(0.115, 0.018, PlaneDist);
    float InnerBand = smoothstep(0.055, 0.010, PlaneDist);
    float OuterBand = smoothstep(0.145, 0.075, PlaneDist) * (1.0 - smoothstep(0.115, 0.145, PlaneDist));

    // Saturn-style darker gaps across the band.
    float CassiniGap = 1.0 - smoothstep(0.010, 0.000, abs(PlaneDist - 0.067)) * 0.82;
    float InnerGap   = 1.0 - smoothstep(0.009, 0.000, abs(PlaneDist - 0.031)) * 0.45;

    float Dust = fbm_fast(vec2(Along * 42.0, PlaneDist * 180.0), 3);
    float FineDust = random(floor(vec2(Along * 260.0, PlaneDist * 950.0))) * 0.10;

    float RingMask = (WideBand * 0.58 + InnerBand * 0.35 + OuterBand * 0.32);
    RingMask *= CassiniGap * InnerGap;
    RingMask *= 0.82 + Dust * 0.32 + FineDust;
    RingMask *= smoothstep(-0.15, 0.20, PlayerPosN.y);

    vec3 RingBright = to_linear(vec3(1.00, 0.82, 0.55));
    vec3 RingDark   = to_linear(vec3(0.34, 0.27, 0.20));
    vec3 RingColor  = mix(RingDark, RingBright, 0.55 + Dust * 0.45);

    // Fade the ring gently so it sits inside the End sky instead of looking pasted on.
    return RingColor * RingMask * 1.35;
}


vec3 get_end_sky(vec3 ViewPosN, vec3 PlayerPosN) {
    const vec3 SkyT = to_linear(vec3(f_END_SKY_T_R, f_END_SKY_T_G, f_END_SKY_T_B));
    const vec3 SkyG1 = to_linear(vec3(f_END_AURORA1_R, f_END_AURORA1_G, f_END_AURORA1_B));
    const vec3 SkyG2 = to_linear(vec3(f_END_AURORA2_R, f_END_AURORA2_G, f_END_AURORA2_B));

    float upDot = dot(ViewPosN, gbufferModelView[1].xyz); //not much, what's up with you?

    float VerticalFactor = 1 - abs(upDot);

    #ifdef END_SATURN_RINGS
        vec3 SkyG = get_end_saturn_rings(PlayerPosN) * (0.45 + VerticalFactor * 0.75);
    #else
        vec3 SkyG = vec3(0); // No End aurora on non-ring profiles.
    #endif

    vec3 Final = SkyT + SkyG * (fogify(upDot + 0.2, 0.05)); 

    Final *= 1 - fogify(max(upDot + 0.2, 0), 0.02); // Void at the bottom

    return Final;
}

vec3 get_sky_main(vec3 ViewPosN, vec3 PlayerPosN, vec3 SunGlare) {
    #ifdef DIMENSION_OVERWORLD
        vec3 SkyColor = get_sky(ViewPosN, SunGlare);
    #elif defined DIMENSION_END
        vec3 SkyColor = get_end_sky(ViewPosN, PlayerPosN);
    #else
        vec3 fogColorL = to_linear(fogColor.rgb);
        fogColorL += 1e-6; // Need to prevent nans when fog is vec3(0)
        vec3 SkyColor = mix(fogColorL, normalize(fogColorL), 0.4) / 3;
    #endif

    return SkyColor;
}
