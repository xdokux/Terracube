#define WATER_REFLECTION

// Very simple and inaccurate, but it's better than nothing.
float water_fog() {
    vec2 ScreenPos = gl_FragCoord.xy * resolutionInv;
    float TerrainDepth = texture2D(depthtex1, ScreenPos).x;
    TerrainDepth = linearize_depth(TerrainDepth);
    float ScreenDepth = linearize_depth(gl_FragCoord.z);
    return smoothstep(3, 40, TerrainDepth - ScreenDepth) * WATER_FOG_STRENGTH *2.0;
}

vec3 tint_underwater(vec3 FinalColor) {
    if (isEyeInWater == 1) {
        vec3 WaterColor = to_linear(vec3(f_WATER_RED, f_WATER_GREEN, f_WATER_BLUE));
        WaterColor = mix_preserve_c1lum(WaterColor, fogColor, f_BIOME_WATER_CONTRIBUTION);
        float DistFromSurface = 1 - eyeBrightnessSmooth.y / 240.;
        vec3 Tinted = WaterColor * DistFromSurface;
        FinalColor = mix_preserve_c1lum(FinalColor, WaterColor, DistFromSurface);
    }
    return FinalColor;
}

float schlick(vec3 V, vec3 N) {
    const float R = 0.05;
    float Theta = clamp(1 - dot(-V, N), 0, 1);
    return R + (1 - R) * (pow(Theta, 5.0));
}

vec3 get_water_normal(vec2 Coords, vec3 WorldNormal) {
    vec2 N = noise_water(Coords);
    return normalize(vec3(N.x, N.y, 1.0 - (N.x * N.x + N.y * N.y)));
}

vec3 sky_reflection(vec3 ReflectedVec, float WNy, float Dist, vec3 ViewPos,sampler2D lightmap,vec2 lmcoord) {
    #ifdef DIMENSION_OVERWORLD
                vec3 SunGlare = get_sun_glare(Dist);
                SunGlare *= 0.05; // Dim the sun glare for reflections

                float shadow = 1.0;
                vec3 currentPos = mat3(gbufferModelViewInverse) * ViewPos + cameraPosition; // Convert to world space
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

            SunGlare *= shadow; // Apply shadow to sun glare


            float cloudTransmittance = 1.0;
            vec3 Sky =vec3(0);

            Sky = get_sky(ReflectedVec, SunGlare);
            vec3 ViewPos1= normalize(ReflectedVec);
            vec3 PlayerPos = mat3(gbufferModelViewInverse) * ViewPos1;
            vec3 PlayerPosN = normalize(PlayerPos);

            float SkyLight = texture2D(lightmap,lmcoord).y;
            // 2. Setup World Coordinates for Volumetrics. For reflections, the ray starts at the fragment's world position.
            vec3 worldRo = mat3(gbufferModelViewInverse) * ViewPos + cameraPosition;
            vec3 worldRd = normalize((gbufferModelViewInverse * vec4(ReflectedVec, 0.0)).xyz); // Reflected view direction in world space
            vec3 sunDir = normalize(mat3(gbufferModelViewInverse) * sunPosition);


            // 1. Get the base reflection (Sky + Clouds)
            #ifdef REFLECT_CLOUDS
            vec3 Reflection = vec3(0.0);
                #ifdef VOLUMETRIC_CLOUDS
                    Reflection += get_nostalgic_volumetrics(worldRd, worldRo, sunDir, Sky, SunGlare, 0, cloudTransmittance, true, worldRo.y);
                #else
                    Reflection += Sky;
                    Reflection += get_clouds(ReflectedVec, PlayerPos, PlayerPosN, SunGlare, Sky);
                #endif
            #else
                vec3 Reflection = Sky;
            #endif

            #ifdef REFLECT_SHOOTING_STARS
                Reflection += get_shooting_stars(PlayerPos) * (1-rainStrength) * 10.0 * cloudTransmittance;
            #endif
            
            // Tonemap the result to handle bright values gracefully
            //Reflection = 1.0 - exp(-Reflection * 1.1);
            
            vec3 poolTint = vec3(WATER_TINT_R, WATER_TINT_G, WATER_TINT_B); 
            //Reflection *= poolTint;

            float WaterBrightness=(dayStrength + sunsetStrength + sunriseStrength) * WATER_BRIGHTNESS_STRENGHT;
            float NightFactor = NIGHT_FACTOR; 
            float WaterBrightnessCombined=WaterBrightness + (NightFactor * 4.0) - (sunriseStrength * 2.5) - (sunsetStrength * 2.5) - (rainStrength*1.5);
            // 4. Boost overall brightness slightly for that summer vibe
            //Reflection *= clamp(WaterBrightnessCombined,0.0,1.0);

            //Reflection = clamp(Reflection,Reflection,vec3(2.5));
            #ifdef REFLECT_STARS
            Reflection += get_stars(PlayerPos) * (1-rainStrength) * 5.0 * cloudTransmittance;
            #endif

            SunGlare *= cloudTransmittance;
            // --- SUN HIGHLIGHT ---
            #ifdef REFLECT_SUN
            if (WNy > 0.01) { 
                vec3 sunData = round_sun(ReflectedVec,sunPosN,PlayerPosN);
                float sunIntensity = sunData.r + sunData.g + sunData.b;
                sunIntensity *= 9.5 * cloudTransmittance * shadow;
                Reflection += sunIntensity;
            }
            #endif
            
        return Reflection;
    #else
        return fogColor.rgb;
    #endif
}

vec3 ssr(vec3 RVec, float Dist, vec3 ViewPos, float Fresnel, float WNy, bool IsDH, sampler2D lightmap,vec2 lmcoord,float SkyBrightness) {
    vec3 ScreenPos = vec3(gl_FragCoord.xy * resolutionInv, gl_FragCoord.z);
    
    // 1. Protect normalize() from dividing by zero
    float rayDist = 50.0;

    if(RVec.z >0.0){
        float maxDist = (-0.5 - ViewPos.z) / RVec.z;
        rayDist = clamp(maxDist,0.1,rayDist);
    }
    vec3 endPos = ViewPos + RVec * rayDist;
    vec3 deltaPos = view_screen(endPos, IsDH) - ScreenPos;
    if (dot(deltaPos, deltaPos) < 1e-6) {
       return sky_reflection(RVec, WNy, Dist, ViewPos, lightmap, lmcoord);
    }
    vec3 Offset = normalize(deltaPos);

    // 2. Protect the step calculation from dividing by zero
    vec3 safeOffset = Offset;
    if (abs(safeOffset.x) < 0.00001) safeOffset.x = 0.00001;
    if (abs(safeOffset.y) < 0.00001) safeOffset.y = 0.00001;
    if (abs(safeOffset.z) < 0.00001) safeOffset.z = 0.00001;

    vec3 Len = (step(0.0, Offset) - ScreenPos) / safeOffset; // Safely divided!
    
    float MinLen = min(Len.x, min(Len.y, Len.z)) / SSR_STEPS;
    Offset *= MinLen;

    float Noise = dither(gl_FragCoord.xy);
    vec3 ExpectedPos = ScreenPos + Offset * Noise;
    
    for (int i = 1; i <= SSR_STEPS; i++) {
        float RealDepth = get_depth_solid(ExpectedPos.xy, IsDH);
        if (RealDepth < 0.56) {
            break;
        }

        if (ExpectedPos.z > RealDepth) {
            if (ExpectedPos.z - RealDepth > Offset.z * (0.5 * SSR_STEPS)) {
                break;
            }
            for (int j = 1; j <= int(round(Fresnel * 3)); j++) {
                Offset /= 2.0; // Use 2.0 to ensure float math
                vec3 EPos1 = ExpectedPos - Offset;
                float RDepth1 = get_depth_solid(EPos1.xy, IsDH);
                if (EPos1.z > RDepth1) {
                    ExpectedPos = EPos1;
                }
            }
    
            vec3 rawSSR = texture2D(gaux1, ExpectedPos.xy).rgb;
           #ifdef DISTANT_HORIZONS
                 if(IsDH){
                    return rawSSR;
                 }else {
                   return rawSSR * 1.0;
                 }
            #else
                return rawSSR * 1.0;
            #endif
        }
        ExpectedPos += Offset;
    }
    return sky_reflection(RVec, WNy, Dist, ViewPos, lightmap, lmcoord);
}

vec3 flipped_image_ref(vec3 RVec, float Dist, vec3 ViewPos, float WNy, bool IsDH,sampler2D lightmap,vec2 lmcoord) {
    #ifdef DISTANT_HORIZONS
    float Offset = min(1000, 50 + dhRenderDistance / 4);
    #else
    float Offset = 50 + far / 4;
    #endif

    vec3 SamplePos = view_screen(ViewPos + RVec * Offset, IsDH);
    if(SamplePos.xy == clamp(SamplePos.xy, 0, 1)) {
        bool IsDH2;
        float RealDepth = get_depth_solid(SamplePos.xy, IsDH);
        if(SamplePos.z < 1 && SamplePos.z > 0.56 && RealDepth < SamplePos.z) {
            SamplePos.z = RealDepth;
            vec3 ViewPosReal = to_view_pos(SamplePos, IsDH);
            if(len2(ViewPosReal) + 25 > len2(ViewPos)) {
                return clamp(texture2D(gaux1, SamplePos.xy).rgb,0.0,1.0);
            }
        }
    }
    return sky_reflection(RVec, WNy, Dist,ViewPos,lightmap,lmcoord);
}
vec4 get_fancy_water(vec3 ScreenPos, vec3 ViewPos, vec4 BaseColor, float SkyBrightness, mat3 TBN, bool IsDH, sampler2D lightmap, vec2 lmcoord) {
    // 1. Calculate Fog Depth
    float fogFactor = water_fog(); 
    
    // 2. Define the "Milkiness" / Density (Boosted for Poolcore)
    float density = clamp(fogFactor * 2.0, 0.0, 1.0);

    // 3. Poolcore Colors: Bright cyan shallows, deep saturated blue depths
    vec3 shallowColor = vec3(0.05, 0.75, 0.95);
    vec3 deepColor = vec3(0.01, 0.10, 0.85);
    vec3 nightColor = vec3(0.02, 0.05, 0.15); // Deep blue for night
    vec3 poolGradient = mix(shallowColor, deepColor, density) * 0.05;
    poolGradient = mix(poolGradient, nightColor, nightStrength);
    

    // Mix heavily to override the underlying Minecraft block textures
    BaseColor.rgb = mix(BaseColor.rgb, poolGradient, 0.85) * SkyBrightness;
    
    // 4. Handle Reflections & Chromatic Normals
    vec3 ViewPosN = normalize(ViewPos);
    vec3 PlayerPos = to_player_pos(ViewPos);

    #if REFLECTIONS != 0
        vec3 WorldNormal = to_player_pos(TBN[2]);
        
        #ifdef WATER_NORMALS
           
        vec3 WaterNormal = TBN * get_water_normal(PlayerPos.xz + cameraPosition.xz, WorldNormal);
    
        #else
            vec3 WaterNormal = TBN[2];
            vec3 NormalR = WaterNormal; vec3 NormalG = WaterNormal; vec3 NormalB = WaterNormal;
        #endif

        vec3 ReflectedVec = reflect(ViewPosN, WaterNormal);
        float Dist = dot(ReflectedVec, sunPosN);
        float Fresnel = schlick(ViewPosN, WaterNormal);

        if (WorldNormal.y > -0.01) {
            #if REFLECTIONS == 1
            vec3 Reflection = sky_reflection(ReflectedVec, WorldNormal.y, Dist, ViewPos,lightmap,lmcoord);
            #elif REFLECTIONS == 2
            vec3 Reflection = ssr(ReflectedVec, Dist, ViewPos, Fresnel, WorldNormal.y, IsDH,lightmap,lmcoord,SkyBrightness);
            #else
            vec3 Reflection = flipped_image_ref(ReflectedVec, Dist, ViewPos, WorldNormal.y, IsDH,lightmap,lmcoord);
            vec3 cheapSky = vec3(0.5, 0.8, 1.0) / (1.0 + nightStrength * 3.0 ); 
            Reflection = max(Reflection, cheapSky * 0.5); 
            #endif
    
            // Boost reflection for that dreamy, blown-out look
            //Reflection *= 2.0; 
            BaseColor /= (1.0 + nightStrength * 7.5);
            BaseColor.rgb = mix(BaseColor.rgb, Reflection, Fresnel);

            // 5. CHROMATIC SPECULAR HIGHLIGHTS (The Dreamcore Secret Sauce)
            // Calculate the sun glare separately for Red, Green, and Blue using the shifted normals
            float specPower = 120.0; 
// Offset the sun position slightly to fake the chromatic split
vec3 sunR = normalize(sunPosN + vec3(0.02, 0.0, 0.0));
vec3 sunG = sunPosN;
vec3 sunB = normalize(sunPosN - vec3(0.02, 0.0, 0.0));

float specR = pow(max(dot(reflect(ViewPosN, WaterNormal), sunR), 0.0), specPower);
float specG = pow(max(dot(reflect(ViewPosN, WaterNormal), sunG), 0.0), specPower);
float specB = pow(max(dot(reflect(ViewPosN, WaterNormal), sunB), 0.0), specPower);
            
            vec3 specGlint = vec3(specR, specG, specB) * isOutdoorsSmooth;

            // Massive boost to the specular highlights for blinding summer sun
            BaseColor.rgb += (specGlint * 1.8) * dayStrength;
        }
    #endif
    
    // Apply an exposure curve to prevent the brightened water from blowing out to pure white in the distance
   

    // Forced to 1.0 for that solid surface look
    #if REFLECTIONS !=0
        BaseColor.a = 0.5 + (Fresnel * 0.5);
    #endif 
    BaseColor.a = clamp(0.5 + (Fresnel * 2.5), 0.0, 1.0);
    return BaseColor;
}