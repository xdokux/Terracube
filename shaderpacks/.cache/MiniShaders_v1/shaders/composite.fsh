#version 120

// GamesofDev is non chalant
varying vec2 texcoord;

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex3;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;  // Depth without translucent
uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
uniform sampler2D shadowcolor0; // Colored shadow data
uniform sampler2D colortex5;    // PBR Data (Smoothness, Metalness, Emissive)
uniform sampler2D noisetex;

uniform vec3 shadowLightPosition;
uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 cameraPosition;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;

uniform int worldTime;
uniform float viewWidth;
uniform float viewHeight;
uniform int isEyeInWater;
uniform float frameTimeCounter;
uniform float rainStrength;
uniform float near;
uniform float far;
uniform vec3 fogColor;

// Nether settings (from shaders.properties)
#ifndef NETHER_VIEW_LIMIT
  #define NETHER_VIEW_LIMIT 192
#endif
#ifndef NETHER_STORM
  #define NETHER_STORM 1
#endif
#ifndef NETHER_STORM_LOWER_ALT
  #define NETHER_STORM_LOWER_ALT 50
#endif
#ifndef NETHER_STORM_HEIGHT
  #define NETHER_STORM_HEIGHT 64
#endif
#ifndef NETHER_STORM_I
  #define NETHER_STORM_I 1.0
#endif
#ifndef NETHER_COLOR_MODE
  #define NETHER_COLOR_MODE 3
#endif

// Quality setting (from shaders.properties)
#ifndef QUALITY
  #define QUALITY 2
#endif

/* DRAWBUFFERS:04 */

// ═══════════════════════════════════════════════════════════════════════════
// CONSTANTS (quality-dependent)
// ═══════════════════════════════════════════════════════════════════════════

#define SHADOW_DISTORT_FACTOR 0.10
#define PI 3.14159265
#define TAU 6.28318530

#if QUALITY == 1
  #define PCF_SAMPLES 4
  #define SHADOW_MAP_RES 1024.0
  #define PENUMBRA_SCALE 0.5
  #define ENABLE_BOUNCE 0
  #define NETHER_STORM_STEPS 0
#elif QUALITY == 3
  #define PCF_SAMPLES 32
  #define SHADOW_MAP_RES 4096.0
  #define PENUMBRA_SCALE 2.5
  #define ENABLE_BOUNCE 1
  #define BOUNCE_MULT 1.5
  #define NETHER_STORM_STEPS 8
  #define ENABLE_VOLUMETRIC_LIGHT 1
#else
  #define PCF_SAMPLES 16
  #define SHADOW_MAP_RES 2048.0
  #define PENUMBRA_SCALE 1.5
  #define ENABLE_BOUNCE 1
  #define BOUNCE_MULT 1.0
  #define NETHER_STORM_STEPS 4
#endif

// ═══════════════════════════════════════════════════════════════════════════
// UTILITY FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════

vec4 getWorldPosition(vec2 coord, float depth) {
    vec4 clipPos = vec4(coord * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 viewPos = gbufferProjectionInverse * clipPos;
    viewPos /= viewPos.w;
    return gbufferModelViewInverse * viewPos;
}

vec3 getViewPosition(vec2 coord, float depth) {
    vec4 clipPos = vec4(coord * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 viewPos = gbufferProjectionInverse * clipPos;
    return viewPos.xyz / viewPos.w;
}

float linearizeDepth(float depth) {
    return (2.0 * near * far) / (far + near - (depth * 2.0 - 1.0) * (far - near));
}

vec3 distort(vec3 shadowPos) {
    float distortFactor = length(shadowPos.xy) + SHADOW_DISTORT_FACTOR;
    shadowPos.xy /= distortFactor;
    shadowPos.z *= 0.5;
    return shadowPos;
}

// cossin helper
vec2 cossin(float angle) {
    return vec2(cos(angle), sin(angle));
}

// pow4 for vivid color boost
vec3 pow4(vec3 v) {
    v *= v;
    return v * v;
}

// ═══════════════════════════════════════════════════════════════════════════
// SKY REFLECTION (for PBR metals/smooth surfaces)
// ═══════════════════════════════════════════════════════════════════════════

vec3 getSkyReflection(vec3 reflectDir, float dayFactor) {
    vec3 worldReflectDir = mat3(gbufferModelViewInverse) * reflectDir;
    float upFactor = worldReflectDir.y * 0.5 + 0.5;
    
    vec3 daySkyZenith  = vec3(0.25, 0.45, 0.95);
    vec3 daySkyHorizon = vec3(0.65, 0.75, 0.95);
    vec3 nightSkyZenith  = vec3(0.01, 0.015, 0.04);
    vec3 nightSkyHorizon = vec3(0.03, 0.04, 0.08);
    
    vec3 daySky  = mix(daySkyHorizon, daySkyZenith, pow(upFactor, 0.8));
    vec3 nightSky = mix(nightSkyHorizon, nightSkyZenith, pow(upFactor, 0.6));
    vec3 sky = mix(nightSky, daySky, dayFactor);
    
    // Sun disc reflection
    vec3 sunDir = normalize(sunPosition); // In view space
    float sunDot = max(dot(reflectDir, sunDir), 0.0);
    
    vec3 sunColor = vec3(1.0, 0.95, 0.8);
    vec3 sunDisc = pow(sunDot, 512.0) * sunColor * 3.0 * dayFactor;
    vec3 sunGlow = pow(sunDot, 32.0) * sunColor * 0.15 * dayFactor;
    
    vec3 worldSunDir = mat3(gbufferModelViewInverse) * sunDir;
    float horizonFade = 1.0 - pow(max(worldSunDir.y, 0.0), 0.5);
    sunDisc *= mix(vec3(1.0), vec3(1.0, 0.6, 0.3), horizonFade * 0.5);
    
    float NdotU = clamp((worldReflectDir.y + 0.7) * 2.0, 0.0, 1.0) * 0.75 + 0.25;
    
    return (sky + sunDisc + sunGlow) * NdotU;
}

// ═══════════════════════════════════════════════════════════════════════════
// NETHER HELPERS
// ═══════════════════════════════════════════════════════════════════════════

// Simple 3D hash for noise
float hash31(vec3 p) {
    p = fract(p * vec3(443.897, 441.423, 437.195));
    p += dot(p, p.yzx + 19.19);
    return fract((p.x + p.y) * p.z);
}

// Smooth 3D value noise
float valueNoise3D(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f); // smoothstep
    
    float n000 = hash31(i);
    float n100 = hash31(i + vec3(1,0,0));
    float n010 = hash31(i + vec3(0,1,0));
    float n110 = hash31(i + vec3(1,1,0));
    float n001 = hash31(i + vec3(0,0,1));
    float n101 = hash31(i + vec3(1,0,1));
    float n011 = hash31(i + vec3(0,1,1));
    float n111 = hash31(i + vec3(1,1,1));
    
    return mix(
        mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
        mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
        f.z
    );
}

// FBM noise for Nether Storm
float netherStormNoise(vec3 p) {
    float n = 0.0;
    n += valueNoise3D(p * 0.5) * 0.5;
    n += valueNoise3D(p * 1.0) * 0.25;
    n += valueNoise3D(p * 2.0) * 0.125;
    n += valueNoise3D(p * 4.0) * 0.0625;
    return n;
}

// Get Nether biome color based on fogColor analysis — SMOOTH weighted blending
vec3 getNetherColor(vec3 fc) {
    float fogBr = max(fc.r, max(fc.g, fc.b));
    float sat = fogBr - min(fc.r, min(fc.g, fc.b));
    
    #if NETHER_COLOR_MODE == 0
        // Constant warm red-orange
        return vec3(0.7, 0.26, 0.08) * 0.6;
    #elif NETHER_COLOR_MODE == 2
        // Vanilla fogColor blended
        return fc * 0.6 + 0.2 * normalize(fc + 0.0001);
    #else
        // Mode 3: Smooth per-biome blending via fogColor distance matching
        // Each biome has a reference fogColor and output color.
        // Weight = how closely current fogColor matches each reference.
        
        // Reference fog colors for each Nether biome (actual Minecraft values)
        vec3 refWastes  = vec3(0.200, 0.031, 0.031);
        vec3 refCrimson = vec3(0.200, 0.012, 0.012);
        vec3 refWarped  = vec3(0.102, 0.020, 0.102);
        vec3 refBasalt  = vec3(0.408, 0.373, 0.439);
        vec3 refSoul    = vec3(0.106, 0.275, 0.412);
        
        // Output biome colors (balanced)
        vec3 colWastes  = vec3(0.45, 0.18, 0.08);
        vec3 colCrimson = vec3(0.40, 0.09, 0.06);
        vec3 colWarped  = vec3(0.20, 0.13, 0.30);
        vec3 colBasalt  = vec3(0.18, 0.16, 0.16);
        vec3 colSoul    = vec3(0.12, 0.28, 0.28);
        
        // Compute weights: inverse distance, smoothed
        // Smaller distance = higher weight
        float dWastes  = length(fc - refWastes);
        float dCrimson = length(fc - refCrimson);
        float dWarped  = length(fc - refWarped);
        float dBasalt  = length(fc - refBasalt);
        float dSoul    = length(fc - refSoul);
        
        // Convert distances to soft weights (closer = stronger)
        float sharpness = 2.0; // higher = sharper transitions, lower = smoother
        float wWastes  = exp(-dWastes  * sharpness);
        float wCrimson = exp(-dCrimson * sharpness);
        float wWarped  = exp(-dWarped  * sharpness);
        float wBasalt  = exp(-dBasalt  * sharpness);
        float wSoul    = exp(-dSoul    * sharpness);
        
        float totalW = wWastes + wCrimson + wWarped + wBasalt + wSoul + 0.0001;
        
        vec3 result = (colWastes * wWastes + colCrimson * wCrimson + 
                       colWarped * wWarped + colBasalt * wBasalt + 
                       colSoul * wSoul) / totalW;
        
        return result;
    #endif
}

// ═══════════════════════════════════════════════════════════════════════════
// IMPROVED COLORED SHADOW SAMPLING (16-sample PCF with dual-depth)
// ═══════════════════════════════════════════════════════════════════════════

vec4 getShadowColored(vec4 worldPos) {
    // Transform to shadow space
    vec4 shadowClip = shadowProjection * (shadowModelView * worldPos);
    shadowClip.xyz /= shadowClip.w;
    
    // Apply distortion
    shadowClip.xyz = distort(shadowClip.xyz);
    
    // Convert to texture coordinates
    vec3 shadowPos = shadowClip.xyz * 0.5 + 0.5;
    
    // Bounds check
    if (any(lessThan(shadowPos.xyz, vec3(0.0))) || any(greaterThan(shadowPos.xyz, vec3(1.0)))) {
        return vec4(1.0, 1.0, 1.0, 1.0);
    }
    
    // Shadow bias
    shadowPos.z -= 0.0006;
    
    float rSteps = 1.0 / float(PCF_SAMPLES);
    vec3 result = vec3(0.0);
    
    // Dithering for rotation
    float dither = fract(sin(dot(gl_FragCoord.xy, vec2(12.9898, 78.233))) * 43758.5453 + frameTimeCounter);
    
    // Penumbra scale (quality-dependent)
    float penumbraScale = PENUMBRA_SCALE / SHADOW_MAP_RES;
    
    // Rotating PCF kernel
    vec2 rot = cossin(dither * TAU) * penumbraScale;
    float angleStepRad = TAU * 0.125;
    vec2 angleStepVec = cossin(angleStepRad);
    
    for (int i = 0; i < PCF_SAMPLES; i++) {
        float fi = float(i) + dither;
        vec2 sampleCoord = shadowPos.xy + rot * sqrt(fi * rSteps);
        
        // Dual-depth sampling
        float sampleDepthOpaque = texture2D(shadowtex0, sampleCoord).r;
        float sampleDepthFull   = texture2D(shadowtex1, sampleCoord).r;
        
        float litFull = step(shadowPos.z, sampleDepthFull);
        float litOpaque = step(shadowPos.z, sampleDepthOpaque);
        
        if (litOpaque != litFull) {
            vec3 glassColor = texture2D(shadowcolor0, sampleCoord).rgb;
            result += pow4(glassColor) * litFull;
        } else {
            result += litFull;
        }
        
        // Rotate sample direction
        rot = vec2(
            rot.x * angleStepVec.x - rot.y * angleStepVec.y,
            rot.x * angleStepVec.y + rot.y * angleStepVec.x
        );
    }
    
    result *= rSteps;
    
    float shadowFactor = max(result.r, max(result.g, result.b));
    vec3 shadowColor = shadowFactor > 0.001 ? result / shadowFactor : vec3(1.0);
    
    return vec4(shadowColor, shadowFactor);
}

// ═══════════════════════════════════════════════════════════════════════════
// MAIN
// ═══════════════════════════════════════════════════════════════════════════

void main() {
    vec2 uv = texcoord;
    
    // ═══════════════════════════════════════════════════════════════════════
    // UNDERWATER DISTORTION
    // ═══════════════════════════════════════════════════════════════════════
    
    if (isEyeInWater > 0) {
        float speed = frameTimeCounter * 1.5;
        vec2 noise = vec2(
            sin(uv.y * 10.0 + speed) + cos(uv.x * 15.0 + speed * 1.2),
            cos(uv.x * 12.0 + speed) + sin(uv.y * 8.0 + speed * 0.8)
        ) * 0.005;
        uv += noise;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SAMPLE G-BUFFERS
    // ═══════════════════════════════════════════════════════════════════════
    
    float depth = texture2D(depthtex0, uv).r;
    float depthSolid = texture2D(depthtex1, uv).r;
    
    vec4 albedoData = texture2D(colortex0, uv);
    vec4 normalData = texture2D(colortex1, uv);
    vec4 lightData = texture2D(colortex2, uv);
    vec4 pbrData = texture2D(colortex5, uv);
    
    vec3 albedo = albedoData.rgb;
    float alpha = albedoData.a;
    vec3 normal = normalize(normalData.rgb * 2.0 - 1.0);
    float skyLight = normalData.a;
    float blockLight = lightData.r;
    float emissive = lightData.g;
    float isHand = lightData.b;
    
    float smoothness = pbrData.r;
    float metalness = pbrData.g;
    
    // Detect translucent pixels — only water/glass/ice (materialId > 0.7)
    // Entities/hands also have depth != depthSolid but are NOT translucent surfaces
    bool isTranslucent = (depth != depthSolid) && (emissive > 0.7);
    
    // Skip sky — pass through as-is
    if (depth >= 1.0) {
        gl_FragData[0] = vec4(albedo, 1.0);
        gl_FragData[1] = vec4(albedo, 1.0); // colortex4: sky for refraction/reflection
        return;
    }
    
    vec4 worldPos = getWorldPosition(uv, depth);
    vec3 viewPos = getViewPosition(uv, depth);
    vec3 viewDir = normalize(viewPos);
    
    // ═══════════════════════════════════════════════════════════════════════
    // DAY/NIGHT SYSTEM (worldTime-based, 100% camera-independent)
    // Follows BSL documentation: lightCol is SAME for entire screen.
    // Only shadow and NdotL vary per pixel.
    // ═══════════════════════════════════════════════════════════════════════
    
    float time = mod(float(worldTime), 24000.0);
    
    // dayFactor: smooth 0→1→0 over the day cycle
    float dayFactor;
    if (time < 1000.0) {
        dayFactor = smoothstep(0.0, 1000.0, time);       // end of sunrise
    } else if (time < 11000.0) {
        dayFactor = 1.0;                                  // full day
    } else if (time < 13000.0) {
        dayFactor = 1.0 - smoothstep(11000.0, 13000.0, time); // sunset
    } else if (time < 23000.0) {
        dayFactor = 0.0;                                  // full night
    } else {
        dayFactor = smoothstep(23000.0, 24000.0, time);   // sunrise start
    }
    
    // sunsetFactor: peaks during transitions
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
    
    // Light direction (view-space — both normal and lightDir in same space)
    vec3 lightDir = normalize(shadowLightPosition);
    float NdotL = max(dot(normal, lightDir), 0.0);
    
    // Up vector: world (0,1,0) transformed to view-space
    vec3 viewUp = normalize(mat3(gbufferModelView) * vec3(0.0, 1.0, 0.0));
    float NdotU = max(dot(normal, viewUp), 0.0);
    
    // ═══════════════════════════════════════════════════════════════════════
    // DIMENSION DETECTION
    // ═══════════════════════════════════════════════════════════════════════
    float fogBrightness = max(fogColor.r, max(fogColor.g, fogColor.b));
    float dNWastes  = length(fogColor - vec3(0.200, 0.031, 0.031));
    float dNCrimson = length(fogColor - vec3(0.200, 0.012, 0.012));
    float dNWarped  = length(fogColor - vec3(0.102, 0.020, 0.102));
    float dNBasalt  = length(fogColor - vec3(0.408, 0.373, 0.439));
    float dNSoul    = length(fogColor - vec3(0.106, 0.275, 0.412));
    float minNetherDist = min(min(dNWastes, dNCrimson), min(min(dNWarped, dNBasalt), dNSoul));
    bool isNether = (minNetherDist < 0.3 && fogBrightness > 0.08);
    vec3 netherColor = isNether ? getNetherColor(fogColor) : vec3(0.0);
    
    // ═══════════════════════════════════════════════════════════════════════
    // APPLY LIGHTING
    // ═══════════════════════════════════════════════════════════════════════
    vec3 color;
    
    if (isNether) {
        vec3 netherAmbient = netherColor * 0.6 + vec3(0.045);
        float upBias = max(dot(normal, viewUp), 0.0) * 0.2 + 0.8;
        
        vec3 storedLightColor = texture2D(colortex3, uv).rgb;
        vec3 lightColor = vec3(1.0, 0.6, 0.3);
        if (length(storedLightColor) > 0.1 && emissive > 0.5) {
            lightColor = storedLightColor;
        }
        float blockIntensity = pow(blockLight, 2.0) * 1.0;
        vec3 blockLighting = lightColor * blockIntensity;
        
        vec3 lighting = netherAmbient * upBias + blockLighting;
        lighting = max(lighting, vec3(0.05));
        
        if (isTranslucent) { color = albedo * mix(vec3(1.0), lighting, 0.5); }
        else { color = albedo * lighting; }
        
        if (emissive > 0.5) { color = albedo * max(lighting, vec3(0.5)); }
        
        float pbrEmissive = pbrData.b;
        if (pbrEmissive > 0.0) { color += albedo * pbrEmissive * 4.0; }
    } else {
        // ═══════════════════════════════════════════════════════════════
        // OVERWORLD LIGHTING
        // lightCol is the SAME for every pixel (camera-independent).
        // Only shadow, NdotL, NdotU vary per pixel.
        // ═══════════════════════════════════════════════════════════════
        
        float weatherDarken = 1.0 - rainStrength * 0.7;
        
        // --- Global light color (same for all pixels in frame) ---
        vec3 lightDay     = vec3(1.0, 0.95, 0.9);
        vec3 lightSunset  = vec3(1.0, 0.6, 0.3);
        vec3 lightNight   = vec3(0.06, 0.08, 0.15);
        
        vec3 lightSun = mix(lightDay, lightSunset, sunsetFactor);
        vec3 lightCol = mix(lightNight, lightSun, dayFactor) * weatherDarken;
        
        // --- Global ambient color (same for all pixels) ---
        vec3 ambientDay    = vec3(0.18, 0.22, 0.32);
        vec3 ambientSunset = vec3(0.20, 0.12, 0.08);
        vec3 ambientNight  = vec3(0.012, 0.018, 0.035);
        
        vec3 ambientSun = mix(ambientDay, ambientSunset, sunsetFactor * 0.4);
        vec3 ambientCol = mix(ambientNight, ambientSun, dayFactor);
        
        // --- Per-pixel shadow ---
        vec4 shadowResult = vec4(1.0, 1.0, 1.0, 1.0);
        if (NdotL > 0.0) {
            shadowResult = getShadowColored(worldPos);
        }
        float shadowFactor = shadowResult.a;
        vec3 shadowTint = shadowResult.rgb;
        
        // --- Per-pixel ambient (varies by NdotU and skyLight) ---
        float softLight = pow(skyLight, 1.3) * (0.6 + 0.4 * NdotU);
        vec3 skyLighting = ambientCol * softLight;
        
        // --- Direct light: lightCol * NdotL * shadow ---
        vec3 directLight = lightCol * 0.5 * NdotL * shadowFactor * shadowTint;
        
        // Bounced light
        vec3 bouncedLight = vec3(0.0);
        #if ENABLE_BOUNCE == 1
        {
            vec3 bounceDir = normalize(lightDir + viewUp);
            float bounceNdotL = max(dot(reflect(normal, viewUp), bounceDir), 0.0);
            float bounce = bounceNdotL * 0.4 + 0.6;
            bounce = bounce * (2.0 - bounce) * 0.03;
            #ifdef BOUNCE_MULT
                bounce *= BOUNCE_MULT;
            #endif
            bouncedLight = lightCol * 0.5 * bounce * shadowFactor;
        }
        #endif
        
        // PBR Cook-Torrance BRDF
        vec3 finalDirectLight = vec3(0.0);
        if (smoothness > 0.0 || metalness > 0.0) {
            vec3 V = normalize(-viewPos);
            vec3 L = lightDir;
            vec3 H = normalize(V + L);
            float NdotV = max(dot(normal, V), 0.001);
            
            vec3 F0 = mix(vec3(0.04), albedo, metalness);
            vec3 F = F0 + (1.0 - F0) * pow(clamp(1.0 - max(dot(H, V), 0.0), 0.0, 1.0), 5.0);
            
            float roughness = max(1.0 - smoothness, 0.05);
            float a = roughness * roughness;
            float a2 = a * a;
            float NdotH = max(dot(normal, H), 0.0);
            float denom = (NdotH * NdotH * (a2 - 1.0) + 1.0);
            float D = a2 / (3.14159 * denom * denom);
            
            float k = (roughness + 1.0) * (roughness + 1.0) / 8.0;
            float g_n_l = NdotL / (NdotL * (1.0 - k) + k);
            float g_n_v = NdotV / (NdotV * (1.0 - k) + k);
            float G = g_n_l * g_n_v;
            
            vec3 pbrSpecular = (D * F * G) / (4.0 * NdotL * NdotV + 0.001);
            vec3 kD = (1.0 - F) * (1.0 - metalness);
            vec3 pbrDiffuse = kD * albedo;
            
            vec3 radiance = lightCol * 0.5 * shadowFactor * shadowTint;
            finalDirectLight = (pbrDiffuse + pbrSpecular) * radiance * NdotL;
            
            // Sky reflection
            vec3 R = reflect(-V, normal);
            vec3 skyRefl = getSkyReflection(R, dayFactor);
            vec3 F_ambient = F0 + (max(vec3(1.0 - roughness), F0) - F0) * pow(clamp(1.0 - NdotV, 0.0, 1.0), 5.0);
            float skyVisibility = skyLight * skyLight;
            vec3 ambientSpecular = skyRefl * F_ambient * skyVisibility * (1.0 - roughness * 0.8);
            finalDirectLight += ambientSpecular;
        } else {
            finalDirectLight = albedo * directLight;
        }
        
        // Block light
        vec3 storedLightColor = texture2D(colortex3, uv).rgb;
        vec3 lightColor = vec3(1.0, 0.6, 0.3);
        if (length(storedLightColor) > 0.1 && emissive > 0.5) {
            lightColor = storedLightColor;
        }
        float blockIntensity = pow(blockLight, 2.0) * 0.6;
        vec3 blockLighting = lightColor * blockIntensity;
        
        // Final combination
        vec3 ambientLighting = albedo * (skyLighting + bouncedLight + blockLighting);
        vec3 lighting = ambientLighting + finalDirectLight;
        lighting = max(lighting, vec3(0.01));
        
        if (isTranslucent) { color = mix(albedo, lighting, 0.5); }
        else { color = lighting; }
        
        if (emissive > 0.5) { color = albedo * max(lighting, vec3(0.4)); }
        
        float pbrEmissive = pbrData.b;
        if (pbrEmissive > 0.0) { color += albedo * pbrEmissive * 4.0; }
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // FOG
    // ═══════════════════════════════════════════════════════════════════════
    
    float dist = length(worldPos.xyz);
    
    // Prevent fog on hand/held items
    if (isHand > 0.5) {
        dist = 0.0;
    }
    
    if (isEyeInWater > 0) {
        // Underwater fog
        float fogStart = 2.0;
        float fogEnd = 30.0;
        float fogFactor = clamp((dist - fogStart) / (fogEnd - fogStart), 0.0, 1.0);
        vec3 waterFogCol = vec3(0.1, 0.25, 0.35) * (dayFactor * 0.8 + 0.2);
        color = mix(color, waterFogCol, fogFactor);
        color *= vec3(0.7, 0.9, 1.0);
    } else if (isNether) {
        // ═══════════════════════════════════════════════════════════════
        // NETHER BORDER FOG (reference formula)
        // ═══════════════════════════════════════════════════════════════
        
        float farM = min(far, float(NETHER_VIEW_LIMIT));
        float fog = clamp(dist / farM, 0.0, 1.0);
        // Reference curve: tight at distance, gentle near
        fog = fog * 0.3 + 0.7 * pow(fog, 256.0 / max(farM, 256.0));
        
        vec3 netherFogCol = netherColor * 0.3;
        color = mix(color, netherFogCol, fog * 1.0);
        
        // Subtle biome color cast on everything
        color = mix(color, color * (netherColor * 1.5 + vec3(0.5)), 0.1);
        
        // ═══════════════════════════════════════════════════════════════
        // NETHER STORM — volumetric smoke/fog layer
        // ═══════════════════════════════════════════════════════════════
        #if NETHER_STORM == 1 && NETHER_STORM_STEPS > 0
        {
            vec3 worldPosAbs = worldPos.xyz + cameraPosition;
            float stormLower = float(NETHER_STORM_LOWER_ALT);
            float stormUpper = stormLower + float(NETHER_STORM_HEIGHT);
            
            // Ray march through storm volume (quality-dependent steps)
            float stormAccum = 0.0;
            
            vec3 rayDir = normalize(worldPos.xyz);
            float rayLen = min(dist, farM * 0.8);
            float stepLen = rayLen / float(NETHER_STORM_STEPS);
            
            for (int i = 0; i < NETHER_STORM_STEPS; i++) {
                float t = (float(i) + 0.5) * stepLen;
                vec3 samplePos = cameraPosition + rayDir * t;
                
                // Height mask: fade in/out at storm boundaries
                float hFade = smoothstep(stormLower, stormLower + 8.0, samplePos.y)
                            * (1.0 - smoothstep(stormUpper - 8.0, stormUpper, samplePos.y));
                
                if (hFade > 0.01) {
                    vec3 noiseCoord = samplePos * 0.012 + vec3(frameTimeCounter * 0.3, 0.0, frameTimeCounter * 0.15);
                    float n = netherStormNoise(noiseCoord);
                    float density = smoothstep(0.3, 0.7, n) * hFade;
                    float dFade = smoothstep(5.0, 30.0, t);
                    stormAccum += density * dFade * stepLen * 0.015;
                }
            }
            
            stormAccum = clamp(stormAccum * NETHER_STORM_I, 0.0, 0.7);
            vec3 stormColor = netherColor * 0.5 + vec3(0.02);
            color = mix(color, stormColor, stormAccum);
        }
        #endif
        
    } else {
        // Overworld distance fog
        float distFog = smoothstep(50.0, 160.0, dist);
        
        vec3 dayFogCol = vec3(0.6, 0.7, 0.85);
        vec3 nightFogCol = vec3(0.05, 0.07, 0.12);
        vec3 sunsetFogCol = vec3(0.8, 0.45, 0.25);
        
        // Fog color: blend day/night, then warm it during sunset (uniform, no view dependency)
        vec3 overworldFog = mix(nightFogCol, dayFogCol, dayFactor);
        overworldFog = mix(overworldFog, sunsetFogCol, sunsetFactor * 0.5);
        
        overworldFog *= (1.0 - rainStrength * 0.4);
        
        color = mix(color, overworldFog, distFog * 0.9);
        
        // Ultra: Volumetric light shafts / god rays
        #ifdef ENABLE_VOLUMETRIC_LIGHT
        {
            vec3 lightDir2 = normalize(shadowLightPosition);
            vec2 sunScreenPos = (gbufferProjection * vec4(lightDir2, 0.0)).xy * 0.5 + 0.5;
            
            vec2 deltaUV = (uv - sunScreenPos) * (1.0 / 16.0);
            vec2 sampleUV = uv;
            float lightAccum = 0.0;
            float decay = 0.96;
            float weight = 1.0;
            
            for (int i = 0; i < 16; i++) {
                sampleUV -= deltaUV;
                vec2 clampedUV = clamp(sampleUV, vec2(0.001), vec2(0.999));
                float sampleDepthVL = texture2D(depthtex0, clampedUV).r;
                if (sampleDepthVL >= 1.0) {
                    lightAccum += weight;
                }
                weight *= decay;
            }
            
            lightAccum /= 16.0;
            lightAccum *= dayFactor * 0.15 * (1.0 - rainStrength);
            
            // Apply sun-tinted volumetric light
            vec3 vlColor = vec3(1.0, 0.95, 0.8) * lightAccum;
            color += vlColor;
        }
        #endif
    }
    
    gl_FragData[0] = vec4(color, 1.0);          // colortex0: Lit scene
    gl_FragData[1] = vec4(color, 1.0);          // colortex4: Lit scene copy for refraction/SSR
}
