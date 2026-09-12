vec3 get_stars(vec3 PlayerPosN) {
    vec3 StarCoord = PlayerPosN / (PlayerPosN.y + length(PlayerPosN.xz)) + vec3(frameTimeCounter * 1e-3, 0, 0);
    //StarCoord.x += frameTimeCounter * 0.001;
    const float ACTUAL_STAR_SIZE = 386;
    vec3 StarCoordFloor = floor(StarCoord * ACTUAL_STAR_SIZE) / ACTUAL_STAR_SIZE;
    vec3 StarCoordMid = StarCoordFloor + 0.5 / ACTUAL_STAR_SIZE;

    float Visibility = smoothstep(0.0, 0.1, StarCoord.y); // Smoothly fade out stars near the bottom of the sky
    Visibility *= max(0.5 - distance(StarCoordMid.xz, StarCoord.xz) * ACTUAL_STAR_SIZE, 0) * 2;

    float StarNoise = hash(StarCoordFloor.xz);
    #ifdef RAINBOW_STARS
        vec3 StarColor = vec3(hash2(StarCoordFloor.xz), StarNoise);
    #else
        #ifdef DIMENSION_END
            vec3 StarColor = vec3(10.0);
        #else
            vec3 StarColor = vec3(0.5);
        #endif
    #endif
    return vec3(max(0, StarNoise - 0.995) * 70 * Visibility * StarColor);
}

vec3 get_aurora(vec3 PlayerPosN, float Dither) {
    if(precipitationSmooth <= 1) return vec3(0);

    const vec3 COLOR_TOP = srgb_linear(vec3(28, 255, 218) / 255.0);
    const vec3 COLOR_BOTTOM = srgb_linear(vec3(122, 255, 28) / 255.0);
    const float AURORA_STRENGTH = 3;

    // Calculate intersection with aurora plane
    const float PLANE_TOP = 17.0;
    const float PLANE_BOTTOM = 10.0;
    const int SAMPLE_COUNT = 4;

    vec3 StartPos = PLANE_BOTTOM / PlayerPosN.y * PlayerPosN; 
    vec3 EndPos = PLANE_TOP / PlayerPosN.y * PlayerPosN;
    vec3 Step = (EndPos - StartPos) / SAMPLE_COUNT;
    vec3 Pos = Step * Dither + StartPos;

    vec2 Wind = frameTimeCounter * vec2(2, 3.25);
    vec3 AuroraColor = vec3(0);
    for(int i = 1; i <= SAMPLE_COUNT; i++) {
        vec2 D = vec2(textureNice(noisetex, (Pos.xz + Wind) * 0.0001).rg);
        vec2 Displacement = D * 10.5;

        float Noise = texture(waterNoise, (Pos.xz - Displacement) / vec2(100, 100)).r;

        Noise = pow2(pow4(Noise));
        Noise *= smoothstep(0.0, 0.2, PlayerPosN.y);
        AuroraColor += Noise * mix(COLOR_BOTTOM, COLOR_TOP, smoothstep(StartPos.y, EndPos.y, Pos.y));

        Pos += Step;
    }

    return AuroraColor * AURORA_STRENGTH * (precipitationSmooth - 1) / SAMPLE_COUNT;
}

vec3 get_milky_way(vec3 PlayerPosN) {
    vec2 Coord = PlayerPosN.xz / (PlayerPosN.y * 0.5 + 0.5);

    vec3 Sample = texture(milkyWay, Coord * 0.5).rgb;
    Sample = srgb_linear(Sample);

    Sample *= smoothstep(0., 0.5, PlayerPosN.y);
    return Sample * 0.02;
}

float get_moon_texture(vec3 MoonPos, vec3 ViewPosN) {
    vec2 Coord = view_player(MoonPos - ViewPosN, false).xy;
    Coord.x = -Coord.x; // Gets it closer to the real moon's texture

    return texture(cloudNoise, Coord * 7).r * 0.8 + 0.2;
}

vec3 get_sky_overworld(vec3 ViewPosN, const bool DrawSun, float PlayerPosY) {
    float VangUp = acosf(dot(gbufferModelView[1].xyz, ViewPosN)) - PI / 2;
    float v = 0.5 + 0.5 * sign(-VangUp) * sqrt(abs(-VangUp) / (PI / 2));

    float FakeSkyGround = SmoothMax(v, 0.53, 0.01);
    v = mix(FakeSkyGround, v, clamp(cameraPosition.y / 1000 - 1, 0, 1));

    float u = dot(sunPosN, ViewPosN) * 0.5 + 0.5;

    vec3 SkyColor = texture_rgbm(atm_skyview_sampler, vec2(u, v)).rgb;

    float Fade = smoothstep(-0.02, 0.1, PlayerPosY);

    if (DrawSun) {
        SkyColor += step(0.9997, dot( sunPosN, ViewPosN)) * dataBuf.SunColor * Fade;
        SkyColor += step(0.9995, dot(-sunPosN, ViewPosN)) * dataBuf.MoonColor * Fade * get_moon_texture(-sunPosN, ViewPosN);
    }

    return SkyColor;
}

vec3 get_sky_nether() {
    vec3 fogColorL = srgb_linear(fogColor.rgb);
    vec3 SkyColor = fogColorL / get_luminance(fogColorL);
    return SkyColor / 100;
}

vec3 get_sky(vec3 ViewPosN, const bool DrawSun, float PlayerPosY) {
    #ifdef DIMENSION_OVERWORLD
    return get_sky_overworld(ViewPosN, DrawSun, PlayerPosY);
    #elif defined DIMENSION_NETHER
    return get_sky_nether();
    #else
    return vec3(0);
    #endif
}
