vec4 get_seasons_color(vec4 glcolor) {
    #ifndef SEASONAL_COLORS
        return glcolor;
    #endif
    if(glcolor.rgb != vec3(1)) {
            glcolor.rgb = rgb_to_hsv(glcolor.rgb);

            const vec3 Spring = vec3(SPRING_HUE, SPRING_SAT, SPRING_VAL);
            const vec3 Summer = vec3(SUMMER_HUE, SUMMER_SAT, SUMMER_VAL);
            const vec3 Autumn = vec3(AUTUMN_HUE, AUTUMN_SAT, AUTUMN_VAL);
            const vec3 Winter = vec3(WINTER_HUE, WINTER_SAT, WINTER_VAL);

            // Blend between seasons
            float TimeOfYear = worldDay % 120;
            float SpringS = clamp(TimeOfYear,0,30) / 30;
            float SummerS = clamp(TimeOfYear-30,0,30) / 30;
            float AutumnS = clamp(TimeOfYear-60,0,30) / 30;
            float WinterS = clamp(TimeOfYear-90,0,30) / 30;
            vec3 TintMixed = mix(mix(mix(mix(Spring, Summer, SpringS), Autumn, SummerS), Winter, AutumnS), Spring, WinterS);

            #ifdef SEASONS_TEMPERATE_BIOME_CHECK
                float IsBiomeTemperate = glcolor.r < 0.3 ? smoothstep(0.15, 0.3, glcolor.r) : 1-smoothstep(0.3, 0.35, glcolor.r);
                TintMixed *= IsBiomeTemperate;
            #endif

            glcolor.rgb += TintMixed;
                
            glcolor.rgb = hsv_to_rgb(glcolor.rgb);
        }
    return glcolor;
}

vec3 get_wavy_plants(vec3 WorldPos, float Id, bool IsBelowMid) {
    #ifndef WAVE_LEAVES
        if(Id == MATERIAL_LEAVES)
            return WorldPos;
    #endif

    vec3 WavePos = (WorldPos / WAVE_SIZE + frameTimeCounter * (WAVE_SPEED + thunderStrength) * vec3(windDirection.x, 1, windDirection.y));
    WavePos = sin(WavePos);
    float Noise = WavePos.x * WavePos.y * WavePos.z;
    vec3 Wind = vec3(windDirection.x, 0.5, windDirection.y) * mix(vec3(Noise), WavePos, 0.5) * (WAVE_AMPLITUDE + thunderStrength * 0.1);



    if(Id == MATERIAL_SHORT_PLANT) {
        if(IsBelowMid)
            WorldPos += Wind;
    }
    else if(Id == MATERIAL_TALL_PLANT_LOWER) {
        if(IsBelowMid)
            WorldPos += Wind / 2;
    }
    else if(Id == MATERIAL_TALL_PLANT_UPPER) {
        if(!IsBelowMid)
            WorldPos += Wind / 2;
        else
            WorldPos += Wind;
    }
    else {
        WorldPos += Wind;
    }
    return WorldPos;
}