#include "/lib/distort.glsl"




vec3 get_lava_fog(float dist, vec3 color) {
    const vec3 LAVA_FOG_COLOR = to_linear(vec3(0.65, 0.35, 0.125));
    const vec3 PSNOW_FOG_COLOR = to_linear(vec3(0.5, 0.6, 0.8));

    if (isEyeInWater == 1) {
        vec3 UnderwaterCol = to_linear(vec3(f_WATER_RED, f_WATER_GREEN, f_WATER_BLUE))*(SKY_GROUND+SKY_TOP);
        UnderwaterCol = mix_preserve_c1lum(UnderwaterCol, fogColor, f_BIOME_WATER_CONTRIBUTION);
        dist = clamp(dist / 64, 0, 1);
        return mix(color, UnderwaterCol, dist);
    }
    else if (isEyeInWater == 2) {
        dist = clamp(dist / 2, 0, 1);
        return mix(color, LAVA_FOG_COLOR, dist);
    }
    else if (isEyeInWater == 3) {
        dist = clamp(dist / 2, 0, 1);
        return mix(color, PSNOW_FOG_COLOR, dist);
    }
    return color;
}

vec3 get_border_fog(float strength, vec3 color, vec3 SkyColor) {
    strength *= strength;
    #ifndef DIMENSION_NETHER
    strength *= strength;
    strength *= strength;
    #endif
    strength = exp(-3.0 * strength);
    return mix(SkyColor, color, strength);
}

vec3 get_blindness_fog(float Dist, vec3 Color) {
    Dist = clamp(1.0 - exp(-3.0 * Dist / 10), 0, 1) * max(darknessFactor, blindness);
    return Color * (1 - Dist);
}



vec3 get_atm_fog(float Dist, vec3 Color, vec3 WorldPos, vec3 FogColor) {
    Dist = min(Dist / 256, 1);
    Dist = 1.0 - exp(-3.0 * Dist);
    float Visibility = sunriseStrength * 0.5 + nightStrength * 5.5;
    Visibility = max(Visibility, rainStrength) * isOutdoorsSmooth;
    Visibility *= ATM_FOG_STRENGTH;

    Visibility *= 1 - fbm_fast(WorldPos.xz, 1);

    float HeightFalloff = WorldPos.y >= 50 ? smoothstep(50, 70, WorldPos.y) - smoothstep(70, 120, WorldPos.y) : 0;

    float Factor = Dist * HeightFalloff * Visibility;
    vec3 FinalC = mix(Color, FogColor, Factor);
    return FinalC;
}

float get_phase(float VdotL, float g) {
    float g2 = g * g;
    return (1.0 - g2) / pow(1.0 + g2 - 2.0 * g * VdotL, 1.5);
}


vec3 get_volumetric_fog(vec3 PlayerPos, vec3 Color, vec3 FogColor,float blocklight) {
    float maxDist = min(length(PlayerPos), 128.0); 
    vec3 rayDir = length(PlayerPos) > 0.0001 ? normalize(PlayerPos) : vec3(0.0, 1.0, 0.0);


    float totalWorldTime = float(worldDay) * 24000.0 + float(worldTime);
    
    const int steps = FOG_QUALITY; 
    float stepSize = maxDist / float(steps);
    
    float frameOffset = mod(frameTimeCounter * 100.0, 100.0);
    float jitter = getIGN(gl_FragCoord.xy + frameOffset); 

    vec3 currentPos = cameraPosition + rayDir * (stepSize * jitter);
    
    // --- 1. SMOOTH TIME-OF-DAY LIGHTING ---
    const vec3 SUN_GLARE = to_linear(vec3(0.7, 0.45, 0.0));
    
    // Lowered the sunlight multipliers so it doesn't blow out the screen
    vec3 dawnColor  = vec3(FOG_DAWN_R, FOG_DAWN_G, FOG_DAWN_B); 
    vec3 noonColor  = vec3(FOG_NOON_R, FOG_NOON_G, FOG_NOON_B); 
    vec3 duskColor  = vec3(FOG_DUSK_R, FOG_DUSK_G, FOG_DUSK_B); 
    vec3 nightColor = vec3(FOG_NIGHT_R, FOG_NIGHT_G, FOG_NIGHT_B); 
    
    // Blend them based on time
    vec3 lightColor = (noonColor * dayStrength) + 
                      (duskColor * sunsetStrength) + 
                      (dawnColor * sunriseStrength) + 
                      (nightColor * nightStrength);
                      
    // Rain washes the color away into a moody, muted gray/blue
    lightColor = mix(lightColor, vec3(FOG_RAIN_R, FOG_RAIN_G, FOG_RAIN_B), rainStrength);
    
    vec3 sunDir = normalize(mat3(gbufferModelViewInverse) * shadowLightPosition);
    float VdotL = dot(rayDir, sunDir);
    
    // A lower phase (0.2) makes the god rays wide, soft, and dreamy, not harsh laser beams
    float phase = get_phase(VdotL, 0.2); 
    phase = min(phase, 2.0); 
    
    // The soft multiplier keeps it glowing but never blinding
    vec3 directionalLightColor = (lightColor * phase * GODRAYS_MULT ) * (1.0-rainStrength*0.5) / ((1.0 + nightStrength * 6.5) * (1.0 + dayStrength));
    directionalLightColor = clamp(directionalLightColor,0.0,1.0); 
    
    // --- 2. SUMMER HUMIDITY DENSITY ---
    // Summer air is heavy with heat and humidity. We want a constant, gentle haze.
    float timeDensity = 0.0;
    timeDensity += dayStrength * FOG_NOON_MULT;      // Lazy afternoon heat haze
    timeDensity += sunsetStrength * FOG_DUSK_MULT;  // Golden hour dust
    timeDensity += sunriseStrength * FOG_DAWN_MULT;  // Morning dew/mist
    timeDensity += nightStrength * FOG_NIGHT_MULT;    // Clearer night air
    timeDensity += smoothstep(0.8, 1.0, wetness) * FOG_RAIN_MULT;
    
    
    float transmittance = 1.0;
    vec3 scatteredLight = vec3(0.0);

    vec3 surfacePos = cameraPosition + PlayerPos;
    
    for (int i = 0; i < steps; i++) {

        float heightDensity = exp(-max(0.0, currentPos.y - 60.0) * 0.05); 
        
        // --- FOG ANIMATION & SHAPING ---
        vec3 wind = vec3(totalWorldTime * 0.05, 0.0, totalWorldTime * 0.05);
        vec3 p = (currentPos + wind) * 0.015;
        
        // Base noise for the main cloud shape
        float baseNoise = fbm_cheap(p);
        // Detail noise to add texture and break up the main shape
        float detailNoise = fbm_cheap(p * 2.5 + baseNoise);
        
        float patchyNoise = smoothstep(0.25, clamp(baseNoise + detailNoise * 0.95, 0.0, 1.0), baseNoise + detailNoise * 0.25);
        
        #ifdef BLUE_HOUR
        // Blend between the normal patchy/height-based fog and a solid, uniform wall of fog for the night
        float shapeDensity = mix(patchyNoise * heightDensity, 0.7, nightStrength);
        #else
        float shapeDensity = patchyNoise * heightDensity;
        #endif
        

        // Base density multiplied cleanly by our new smooth time variable
        float localDensity = (shapeDensity * ATM_FOG_STRENGTH * 3.0) * timeDensity * ATM_DEN;
        #ifdef BLUE_HOUR
        // Make the night fog significantly thicker
        localDensity *= 1.0 + (nightStrength * 4.0);
        #endif
        
        if (localDensity > 0.0) {
            float stepTransmittance = exp(-localDensity * stepSize * 0.05);
            
            // --- SHADOW MAPPING ---
            float shadow = 0.0; 
            
            #ifdef GODRAYS
                vec3 playerRelativePos = currentPos - cameraPosition;
                vec3 shadowViewPos = mat3(shadowModelView) * playerRelativePos + shadowModelView[3].xyz;
                vec4 shadowClipPos = shadowProjection * vec4(shadowViewPos, 1.0);
                
                vec3 shadowPos = shadowClipPos.xyz / shadowClipPos.w;
                shadowPos = distortShadowClipPos(shadowPos);
                shadowPos = shadowPos * 0.5 + 0.5; 
                
                shadow = 1.0; 
                if (clamp(shadowPos, 0.0, 1.0) == shadowPos) {
                    float shadowMapDepth = texture2D(shadowtex0, shadowPos.xy).r;
                    if (shadowMapDepth < shadowPos.z - 0.0005) { 
                        shadow = 0.0; 
                    }
                }
            #endif

            // --- BLOCK LIGHT GLOW ---
            float distToSurface = distance(currentPos, surfacePos);
            float torchInfluence = exp(-distToSurface * 0.3) * blocklight;
            vec3 torchColor = vec3(LM_RED, LM_GREEN, LM_BLUE);
            vec3 torchGlow = torchColor * torchInfluence * 3.0;

            // --- APPLY LIGHTING ---
            float ambientTimeMod = mix(0.8, 0.9, nightStrength); 
            vec3 ambientLight = FogColor * 5.0 * ambientTimeMod; 
            
            vec3 directLight = (FogColor * 5.0 * ambientTimeMod) + directionalLightColor; 
            #ifdef BLUE_HOUR
                directLight *= 1.0 + (nightStrength * 0.5 / FOG_NIGHT_MULT);
            #endif
            
            // 1. Mix the sun/moon shadows first
            vec3 stepLight = mix(ambientLight, directLight, shadow);
            
            // 2. Add torch glow AFTER the shadow mix so it glows even in the shade!
            stepLight += torchGlow;
            
            scatteredLight += stepLight * transmittance * (1.0 - stepTransmittance);
            transmittance *= stepTransmittance;

        }
        
        currentPos += rayDir * stepSize; 
    }
    
    return Color  * transmittance * transmittance + scatteredLight;
}

vec3 get_end_fog(float Dist, vec3 Color, vec3 PlayerPos) {
    if(Dist >= furthest) {
        PlayerPos = normalize(PlayerPos) * furthest;
    }
    Dist = min(Dist / 32, 1);
    Dist = 1.0 - exp(-3.0 * Dist) + 0.0497;

    float WorldHeight = PlayerPos.y + cameraPosition.y;
    float HeightLower = 30 + max(0, -WorldHeight);
    float HeightFalloff = 1 - smoothstep(HeightLower, HeightLower + 10, WorldHeight);

    float Factor = Dist * HeightFalloff;
    vec3 FinalC = mix(Color, vec3(0.0005), Factor);
    return FinalC;
}

vec3 get_fog_main(vec3 PlayerPos, vec3 Color, float Depth, vec3 SkyColor, float blocklight) {
    float Dist = length(PlayerPos);

    #if defined DIMENSION_OVERWORLD && defined ATMOSPHERIC_FOG
        if(isEyeInWater == 0)
            Color.rgb = get_volumetric_fog(PlayerPos, Color.rgb, SkyColor,blocklight);
    #endif

    if (Depth < 1) {
        #if defined BORDER_FOG && !defined CUSTOM_SKYBOXES
            Color.rgb = get_border_fog(Dist / furthest, Color.rgb, SkyColor);
        #endif
    }
    #ifdef DIMENSION_END
        Color.rgb = get_end_fog(Dist, Color.rgb, PlayerPos);
    #endif
    Color.rgb = get_lava_fog(Dist, Color.rgb);
    Color.rgb = get_blindness_fog(Dist, Color.rgb);
    return Color;
}
