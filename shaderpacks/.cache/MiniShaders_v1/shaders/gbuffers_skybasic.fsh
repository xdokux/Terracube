#version 120

// GamesofDev is non chalant
varying vec3 viewPos;
varying vec2 texcoord;

uniform sampler2D texture;
uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform int worldTime;
uniform vec3 skyColor;
uniform vec3 fogColor;
uniform float rainStrength;
uniform mat4 gbufferModelViewInverse;

// Quality setting
#ifndef QUALITY
  #define QUALITY 2
#endif

/* DRAWBUFFERS:0 */

void main() {
    vec3 viewDir = normalize(viewPos);
    
    float upAmount = max(viewDir.y, 0.0);
    float horizonFactor = exp(-upAmount * 3.0);
    
    float time = mod(float(worldTime), 24000.0);
    
    float dayFactor;
    if (time < 1000.0) {
        dayFactor = smoothstep(0.0, 1000.0, time);
    } else if (time < 11000.0) {
        dayFactor = 1.0;
    } else if (time < 13000.0) {
        dayFactor = 1.0 - smoothstep(11000.0, 13000.0, time);
    } else if (time < 23000.0) {
        dayFactor = 0.0;
    } else {
        dayFactor = smoothstep(23000.0, 24000.0, time);
    }
    
    float sunsetFactor = 0.0;
    if (time > 11000.0 && time < 13000.0) {
        float t = (time - 11000.0) / 2000.0;
        sunsetFactor = sin(t * 3.14159);
    } else if (time > 22800.0) {
        float t = (time - 22800.0) / 2200.0;
        sunsetFactor = sin(min(t, 1.0) * 3.14159);
    } else if (time < 1000.0) {
        float t = (time + 24000.0 - 22800.0) / 2200.0;
        sunsetFactor = sin(min(t, 1.0) * 3.14159);
    }
    
    // === DIMENSION DETECTION (runtime via fogColor distance) ===
    float fogBrightness = max(fogColor.r, max(fogColor.g, fogColor.b));
    float dNW = length(fogColor - vec3(0.200, 0.031, 0.031));
    float dNC = length(fogColor - vec3(0.200, 0.012, 0.012));
    float dNR = length(fogColor - vec3(0.102, 0.020, 0.102));
    float dNB = length(fogColor - vec3(0.408, 0.373, 0.439));
    float dNS = length(fogColor - vec3(0.106, 0.275, 0.412));
    float minND = min(min(dNW, dNC), min(min(dNR, dNB), dNS));
    bool isNether = (minND < 0.3 && fogBrightness > 0.08);
    
    vec3 finalColor;
    
    if (isNether) {
        // === NETHER SKY ===
        // Smooth weighted blending — matches composite.fsh getNetherColor() approach
        
        // Reference fog colors (actual Minecraft values)
        vec3 refWastes  = vec3(0.200, 0.031, 0.031);
        vec3 refCrimson = vec3(0.200, 0.012, 0.012);
        vec3 refWarped  = vec3(0.102, 0.020, 0.102);
        vec3 refBasalt  = vec3(0.408, 0.373, 0.439);
        vec3 refSoul    = vec3(0.106, 0.275, 0.412);
        
        // Inverse-distance weights
        float sharpness = 5.0;
        float wWastes  = exp(-length(fogColor - refWastes)  * sharpness);
        float wCrimson = exp(-length(fogColor - refCrimson) * sharpness);
        float wWarped  = exp(-length(fogColor - refWarped)  * sharpness);
        float wBasalt  = exp(-length(fogColor - refBasalt)  * sharpness);
        float wSoul    = exp(-length(fogColor - refSoul)    * sharpness);
        float totalW = wWastes + wCrimson + wWarped + wBasalt + wSoul + 0.0001;
        
        // Sky top colors per biome (bright)
        vec3 netherSkyTop = (
            vec3(0.12, 0.04, 0.02) * wWastes +
            vec3(0.10, 0.02, 0.015) * wCrimson +
            vec3(0.04, 0.02, 0.08) * wWarped +
            vec3(0.08, 0.07, 0.07) * wBasalt +
            vec3(0.02, 0.07, 0.07) * wSoul
        ) / totalW;
        
        // Sky horizon colors per biome (bright)
        vec3 netherSkyHorizon = (
            vec3(0.25, 0.10, 0.04) * wWastes +
            vec3(0.22, 0.05, 0.035) * wCrimson +
            vec3(0.10, 0.06, 0.15) * wWarped +
            vec3(0.12, 0.10, 0.10) * wBasalt +
            vec3(0.06, 0.14, 0.14) * wSoul
        ) / totalW;
        
        finalColor = mix(netherSkyTop, netherSkyHorizon, horizonFactor);
        
        // Heat shimmer noise
        float glowNoise = sin(viewDir.x * 4.0 + viewDir.z * 6.0) * 0.015
                        + sin(viewDir.x * 7.0 - viewDir.z * 3.0) * 0.01 + 0.02;
        finalColor += netherSkyHorizon * glowNoise;
        
        // Lava glow from below
        float belowFactor = max(-viewDir.y, 0.0);
        finalColor += vec3(0.10, 0.03, 0.01) * belowFactor * 0.6;
    } else {
        // === OVERWORLD SKY ===
        
        // Day colors - VIBRANT
        vec3 dayZenith = vec3(0.15, 0.4, 0.8);
        vec3 dayHorizon = vec3(0.6, 0.75, 0.95);
        
        // Sunset/sunrise colors
        vec3 sunsetZenith = vec3(0.2, 0.25, 0.5);
        vec3 sunsetHorizon = vec3(1.0, 0.55, 0.25);
        
        // Night colors
        vec3 nightZenith = vec3(0.005, 0.01, 0.025);
        vec3 nightHorizon = vec3(0.02, 0.03, 0.06);
        
        // Blend based on time
        vec3 zenithColor = mix(nightZenith, dayZenith, dayFactor);
        vec3 horizonColor = mix(nightHorizon, dayHorizon, dayFactor);
        
        // Directional sunset factor
        vec3 sunDir = normalize(sunPosition);
        float sunDotRaw = max(dot(viewDir, sunDir), 0.0);
        float directionalSunset = sunsetFactor * (pow(sunDotRaw, 1.5) * 0.8 + 0.2);
        
        // Add sunset/sunrise colors
        zenithColor = mix(zenithColor, sunsetZenith, sunsetFactor * 0.4);
        horizonColor = mix(horizonColor, sunsetHorizon, directionalSunset);
        
        // === WEATHER DARKENING ===
        vec3 rainyColor = vec3(0.3, 0.32, 0.35) * (dayFactor * 0.5 + 0.1);
        zenithColor = mix(zenithColor, rainyColor * 0.3, rainStrength);
        horizonColor = mix(horizonColor, rainyColor, rainStrength);
        
        // Final sky gradient
        vec3 skyGradient = mix(zenithColor, horizonColor, horizonFactor);
        
        // === SUN GLOW (quality-dependent) ===
        // sunDir already calculated above
        float sunDot = max(dot(viewDir, sunDir), 0.0);
        
        float sunDisc = smoothstep(0.9993, 0.9997, sunDot);
        vec3 sunColor = vec3(1.0, 0.98, 0.9) * 2.5;
        
        #if QUALITY == 1
            // Min: simple sun glow only
            float sunGlow = pow(sunDot, 8.0) * 0.3 * dayFactor;
            vec3 glowColor = vec3(1.0, 0.85, 0.6);
            
            finalColor = skyGradient;
            finalColor += glowColor * sunGlow;
            finalColor = mix(finalColor, sunColor, sunDisc * dayFactor * (1.0 - rainStrength));
        #elif QUALITY == 3
            // Ultra: enhanced glow with halo effect
            float sunGlow = pow(sunDot, 6.0) * 0.7 * dayFactor;
            vec3 glowColor = mix(vec3(1.0, 0.85, 0.6), vec3(1.0, 0.5, 0.2), sunsetFactor);
            
            float horizonGlow = pow(sunDot, 2.0) * horizonFactor * 0.35 * dayFactor;
            
            // Halo ring effect
            float halo = pow(sunDot, 128.0) * 0.8 * dayFactor;
            vec3 haloColor = vec3(1.0, 0.92, 0.75);
            
            finalColor = skyGradient;
            finalColor += glowColor * sunGlow;
            finalColor += glowColor * horizonGlow;
            finalColor += haloColor * halo;
            finalColor = mix(finalColor, sunColor, sunDisc * dayFactor * (1.0 - rainStrength));
        #else
            // Medium: current glow
            float sunGlow = pow(sunDot, 6.0) * 0.6 * dayFactor;
            vec3 glowColor = mix(vec3(1.0, 0.85, 0.6), vec3(1.0, 0.5, 0.2), sunsetFactor);
            
            float horizonGlow = pow(sunDot, 2.0) * horizonFactor * 0.25 * dayFactor;
            
            finalColor = skyGradient;
            finalColor += glowColor * sunGlow;
            finalColor += glowColor * horizonGlow;
            finalColor = mix(finalColor, sunColor, sunDisc * dayFactor * (1.0 - rainStrength));
        #endif
        
        // === MOON (quality-dependent) ===
        vec3 moonDir = normalize(moonPosition);
        float moonDot = max(dot(viewDir, moonDir), 0.0);
        float nightAmount = 1.0 - dayFactor;
        
        #if QUALITY == 1
            // Min: simple moon disc only
            float moonDisc = smoothstep(0.9993, 0.9997, moonDot);
            finalColor = mix(finalColor, vec3(0.8, 0.85, 0.95), moonDisc * nightAmount * (1.0 - rainStrength));
        #elif QUALITY == 3
            // Ultra: enhanced moon with brighter glow
            float moonDisc = smoothstep(0.9993, 0.9997, moonDot);
            finalColor = mix(finalColor, vec3(0.85, 0.9, 1.0), moonDisc * nightAmount * (1.0 - rainStrength));
            
            float moonGlow = pow(moonDot, 12.0) * 0.35 * nightAmount * (1.0 - rainStrength);
            finalColor += vec3(0.25, 0.3, 0.5) * moonGlow;
            
            // Moon halo
            float moonHalo = pow(moonDot, 64.0) * 0.2 * nightAmount * (1.0 - rainStrength);
            finalColor += vec3(0.2, 0.25, 0.4) * moonHalo;
        #else
            // Medium: current moon
            float moonDisc = smoothstep(0.9993, 0.9997, moonDot);
            finalColor = mix(finalColor, vec3(0.8, 0.85, 0.95), moonDisc * nightAmount * (1.0 - rainStrength));
            
            float moonGlow = pow(moonDot, 12.0) * 0.2 * nightAmount * (1.0 - rainStrength);
            finalColor += vec3(0.2, 0.25, 0.4) * moonGlow;
        #endif
    }
    
    gl_FragData[0] = vec4(finalColor, 1.0);
}

