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
    return Color;
}

vec3 get_sun_glare(float Dist) {
    float Visibility = sunsetStrength + sunriseStrength;

    const vec3 SUN_GLARE = to_linear(vec3(f_SUN_GLARE_R, f_SUN_GLARE_G, f_SUN_GLARE_B));

    return SUN_GLARE * (Dist * 0.5 + 0.5) * Visibility;
}

vec3 get_clouds(vec3 PlayerPos, vec3 PlayerPosN, vec3 SunGlare, vec3 SkyColor) {
    vec2 CloudPos = PlayerPos.xz / (PlayerPos.y + length(PlayerPos.xz) / 6);

    const float ACTUAL_CLOUD_SPEED = CLOUD_SPEED / 100.;
    float Animation = float(frameTimeCounter) * ACTUAL_CLOUD_SPEED;
    CloudPos += cameraPosition.xz / 512;
    CloudPos = (CloudPos + Animation) * 32;

    float Noise = fbm_clouds(CloudPos, CLOUD_QUALITY);
    float CloudAmount = CLOUD_AMOUNT / 100.0 + rainStrength / 10;
    Noise *= smoothstep(0, 0.4 - CLOUD_OPACITY, Noise - 0.55 + CloudAmount);
    Noise *= smoothstep(0.0, 0.2, PlayerPosN.y);

    // Enhanced cloud lighting with silver lining
    const float DENSITY = 1.5;
    float Transmittance = exp(-Noise * DENSITY);
    float Absorbtion = fbm_clouds(CloudPos + to_player_pos(sunOrMoonPosN).xz * 8, 2);
    Absorbtion = pow4(Absorbtion * 2);

    float LHeight = sin(sunAngleAtHome * PI * 2);
    vec3 CloudColorRaw = (SKY_GROUND + SunGlare / 2) * smoothstep(0, 0.1, abs(LHeight));
    vec3 CloudColor = CloudColorRaw * exp(-Absorbtion * DENSITY);
    CloudColor += SKY_GROUND * Transmittance;

    // Silver lining: bright edge where light passes through thin cloud edges
    float EdgeFactor = smoothstep(0.3, 0.6, Noise) * smoothstep(0.7, 0.5, Noise);
    EdgeFactor *= (1.0 - Absorbtion) * CLOUD_SILVER_LINING;
    vec3 SilverColor = CloudColorRaw * 2.0 * EdgeFactor;
    CloudColor += SilverColor;

    return SkyColor * Transmittance + CloudColor * Noise;
}

vec3 get_sky(vec3 ViewPosN, vec3 SunGlare) {
    float upDot = dot(ViewPosN, gbufferModelView[1].xyz) + 0.1; //not much, what's up with you?

    vec3 MixedColor = mix(SKY_TOP, SKY_GROUND + SunGlare, fogify(max(upDot, 0.0), 0.03));
    return MixedColor;
}

float get_stars(vec3 PlayerPos) {
    vec3 StarCoord = PlayerPos / (PlayerPos.y + length(PlayerPos.xz));
    StarCoord.x += frameTimeCounter * 0.001;
    const float ACTUAL_STAR_SIZE = STAR_SIZE * 512;
    StarCoord = floor(StarCoord * ACTUAL_STAR_SIZE) / ACTUAL_STAR_SIZE;

    float Visibility = smoothstep(-0.02, 0.15, StarCoord.y); // Smoother horizon fade
    #ifdef DIMENSION_OVERWORLD
    Visibility *= nightStrength;
    Visibility *= 1.0 - rainStrength; // Hide stars during rain
    #endif

    float Rand = random(StarCoord.xz);
    float StarBrightness = max(0, Rand - 0.994) * 35;
    // Subtle twinkle effect
    float Twinkle = sin(frameTimeCounter * (2.0 + Rand * 4.0) + Rand * 40.6) * 0.15 + 0.85;
    return StarBrightness * Visibility * STAR_STRENGTH * Twinkle;
}

vec3 get_end_sky(vec3 pos, vec3 PlayerPos) {
    const vec3 SkyT = to_linear(vec3(f_END_SKY_T_R, f_END_SKY_T_G, f_END_SKY_T_B));
    const vec3 SkyG1 = to_linear(vec3(f_END_AURORA1_R, f_END_AURORA1_G, f_END_AURORA1_B));
    const vec3 SkyG2 = to_linear(vec3(f_END_AURORA2_R, f_END_AURORA2_G, f_END_AURORA2_B));
    float upDot = dot(pos, gbufferModelView[1].xyz); //not much, what's up with you?
    vec2 RotPos1 = rotate(PlayerPos.xz, frameTimeCounter * 0.02);
    vec2 RotPos2 = rotate(PlayerPos.xz, -frameTimeCounter * 0.007);
    float Noise1 = fbm_fast(RotPos1 * 160, 2) * (1 - abs(upDot));
    float Noise2 = fbm_fast(RotPos2 * 280, 2) * (1 - abs(upDot));
    float Noise = (Noise1 + Noise2);
    vec3 SkyG = SkyG1 * Noise1 + SkyG2 * Noise2;
    vec3 Final = SkyT + SkyG * (fogify(upDot + 0.2, 0.05));
    Final *= max(1 - fogify(max(upDot + 0.3, 0), 0.02), 0.01);
    return Final;
}

vec3 get_sky_main(vec3 ViewPosN, vec3 PlayerPosN, vec3 SunGlare) {
    #ifdef DIMENSION_OVERWORLD
    vec3 SkyColor = get_sky(ViewPosN, SunGlare);
    #elif defined DIMENSION_END
    vec3 SkyColor = get_end_sky(ViewPosN, PlayerPosN);
    #else
    vec3 fogColorL = to_linear(fogColor.rgb);
    vec3 SkyColor = mix(fogColorL, normalize(fogColorL), 0.4) / 3;
    #endif

    return SkyColor;
}
