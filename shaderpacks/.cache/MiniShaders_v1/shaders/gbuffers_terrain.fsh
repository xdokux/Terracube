#version 120

// GamesofDev is non chalant
varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 glColor;
varying vec3 normal;
varying float blockId;

uniform sampler2D texture;
uniform sampler2D specular;
uniform sampler2D normals;

uniform float frameTimeCounter;

varying vec3 tangent;
varying vec3 binormal;

// Quality setting
#ifndef QUALITY
  #define QUALITY 2
#endif

/* DRAWBUFFERS:01235 */

// Strict emissive light color detection
vec3 getEmissiveLightColor(vec3 texColor, float blockLight) {
    if (blockId > 10000.5 && blockId < 10010.5) {
        if (abs(blockId - 10001.0) < 0.1) return vec3(0.4, 0.8, 0.9);
        if (abs(blockId - 10002.0) < 0.1) return vec3(0.2, 0.7, 0.3);
        if (abs(blockId - 10003.0) < 0.1) return vec3(1.0, 0.65, 0.2);
        // Iron (10004) - Warm Beige/Peach
        if (abs(blockId - 10004.0) < 0.1) return vec3(0.9, 0.7, 0.5);
        // Copper (10005) - Soft Orange
        if (abs(blockId - 10005.0) < 0.1) return vec3(0.9, 0.5, 0.3);
        // Redstone (10006) - Deep Ruby Red
        if (abs(blockId - 10006.0) < 0.1) return vec3(0.8, 0.15, 0.15);
        // Lapis (10007) - Royal Blue
        if (abs(blockId - 10007.0) < 0.1) return vec3(0.2, 0.4, 0.9);
        // Coal (10008) - Skip
        if (abs(blockId - 10008.0) < 0.1) return vec3(0.0);
        // Quartz (10009) - Soft White
        if (abs(blockId - 10009.0) < 0.1) return vec3(0.9, 0.9, 0.9);
        // Ancient Debris (10010) - Warm Brown
        if (abs(blockId - 10010.0) < 0.1) return vec3(0.8, 0.5, 0.3);
    }

    // 2. EXISTING LOGIC (Torches, etc.) - Unchanged
    if (blockLight < 0.95) return vec3(0.0);
    
    float brightness = max(texColor.r, max(texColor.g, texColor.b));
    if (brightness < 0.55) return vec3(0.0);
    
    vec3 normColor = texColor / (brightness + 0.001);
    
    if (normColor.b > 0.45 && normColor.b > normColor.r * 1.4 && normColor.b > normColor.g) return vec3(0.35, 0.7, 1.0);
    if (normColor.r > 0.75 && normColor.g < 0.3 && normColor.b < 0.3) return vec3(1.0, 0.15, 0.1);
    if (brightness > 0.75 && normColor.r > 0.33 && normColor.g > 0.36 && normColor.b > 0.38) return vec3(0.8, 0.95, 1.0);
    if (brightness > 0.8 && normColor.r > 0.36 && normColor.b > 0.36 && normColor.g > 0.28) return vec3(1.0, 0.88, 0.95);
    if (brightness < 0.45 && normColor.b > normColor.r * 1.6 && normColor.g > normColor.r * 1.3) return vec3(0.15, 0.7, 0.85);
    if (normColor.r > 0.35 && normColor.b > 0.42 && normColor.g < 0.28) return vec3(0.7, 0.45, 1.0);
    
    return vec3(1.0, 0.65, 0.35);
}

// Function to isolate pixels that are "ore" and not "stone"
float getOreEmissiveFactor(vec3 albedo, float blockId) {
    float maxC = max(albedo.r, max(albedo.g, albedo.b));
    float minC = min(albedo.r, min(albedo.g, albedo.b));
    float sat = maxC - minC;
    float lum = dot(albedo, vec3(0.2126, 0.7152, 0.0722));
    
    // Default threshold for separating colorful ore from grey stone
    float satThreshold = 0.2; // Stricter threshold
    
    // Special handling per ore
    
    // Iron (10004) - Weak saturation (beige), needs careful check
    if (abs(blockId - 10004.0) < 0.1) {
        // Stone is ~0.5 lum, Iron is usually lighter/beige
        if (lum > 0.6 && sat > 0.05) return 1.0;
        return 0.0;
    }
    
    // Copper (10005) - Orange/Greenish
    if (abs(blockId - 10005.0) < 0.1) {
        satThreshold = 0.15;
    }
    
    // Redstone (10006) - Red
    if (abs(blockId - 10006.0) < 0.1) {
        satThreshold = 0.3; // Very distinct red
    }
    
    // Lapis (10007) - Blue
    if (abs(blockId - 10007.0) < 0.1) {
        satThreshold = 0.3; // Very distinct blue
    }
    
    // Coal (10008) - Dark spots
    if (abs(blockId - 10008.0) < 0.1) {
        return (lum < 0.15) ? 0.6 : 0.0; // Faint glow for coal spots
    }
    
    // Quartz (10009)
    if (abs(blockId - 10009.0) < 0.1) {
        return (lum > 0.7) ? 0.8 : 0.0;
    }

    // Standard high-saturation gems (Diamond, Emerald, Gold)
    if (sat > satThreshold) {
        // Soften the edge between ore and stone
        return smoothstep(satThreshold, satThreshold + 0.1, sat);
    }
    
    return 0.0;
}

void main() {
    vec4 albedo = texture2D(texture, texcoord) * glColor;
    if (albedo.a < 0.1) discard;
    
    vec3 N = normalize(normal);
    float blockLight = lmcoord.x;
    float skyLight = lmcoord.y;
    
    bool isOre = (blockId > 10000.5 && blockId < 10010.5);
    
    float oreGlow = 0.0;
    #if QUALITY >= 2
    if (isOre) {
        oreGlow = getOreEmissiveFactor(albedo.rgb, blockId);
    }
    #endif
    
    // STRICT emissive for regular blocks
    float brightness = max(albedo.r, max(albedo.g, albedo.b));
    bool isStandardEmissive = (blockLight > 0.95 && brightness > 0.55);
    
    bool isEmissive = isStandardEmissive || (oreGlow > 0.1);
    float emissive = isEmissive ? 1.0 : 0.0;
    
    vec3 lightColor = vec3(0.0);
    
    if (isEmissive) {
        if (isOre) {
            lightColor = getEmissiveLightColor(albedo.rgb, 1.0);
            
            // PLEASANT GLOW: Pulse animation (quality-dependent intensity)
            #if QUALITY == 3
                float pulse = sin(frameTimeCounter * 1.8) * 0.15 + 0.85;
                vec3 glowRGB = mix(albedo.rgb, lightColor, 0.4);
                glowRGB *= 1.4 * pulse;
            #else
                float pulse = sin(frameTimeCounter * 1.5) * 0.1 + 0.9;
                vec3 glowRGB = mix(albedo.rgb, lightColor, 0.3);
                glowRGB *= 1.15 * pulse;
            #endif
            
            // Apply ONLY to ore pixels
            albedo.rgb = mix(albedo.rgb, glowRGB, oreGlow);
            
        } else {
            lightColor = getEmissiveLightColor(albedo.rgb, blockLight);
        }
    }
    
    // LabPBR Support
    vec3 worldNormal = N;
    float smoothness = 0.0;
    float metalness = 0.0;
    float pbrEmissive = 0.0;
    
    vec4 specData = texture2D(specular, texcoord);
    smoothness = specData.r;
    metalness = specData.g;
    pbrEmissive = specData.b;
    
    // ═══════════════════════════════════════════════════════════════════════
    // AUTO-PBR (If no PBR texture is found)
    // ═══════════════════════════════════════════════════════════════════════
    if (smoothness < 0.01 && metalness < 0.01) {
        bool isIron = abs(blockId - 10011.0) < 0.1;
        bool isGold = abs(blockId - 10012.0) < 0.1;
        bool isCopper = abs(blockId - 10013.0) < 0.1;
        
        if (isIron) {
            metalness = 1.0;
            smoothness = 0.85; // Very smooth for iron
        } else if (isGold) {
            metalness = 1.0;
            smoothness = 0.85; // Strong reflection
        } else if (isCopper) {
            metalness = 0.9;
            smoothness = 0.75;
        }
    }
    // ═══════════════════════════════════════════════════════════════════════
    
    vec4 normData = texture2D(normals, texcoord);
    if (length(normData.rgb) > 0.01) {
        vec3 normalMap = normData.rgb * 2.0 - 1.0;
        mat3 TBN = mat3(tangent, binormal, N);
        worldNormal = normalize(TBN * normalMap);
    }
    
    gl_FragData[0] = albedo;
    gl_FragData[1] = vec4(worldNormal * 0.5 + 0.5, skyLight);
    
    // For ores, fake block light for glow, weighted by ore factor
    float outputBlockLight = isOre ? mix(blockLight, 1.0, oreGlow) : blockLight;
    gl_FragData[2] = vec4(outputBlockLight, emissive, 0.0, 1.0);
    
    gl_FragData[3] = vec4(lightColor, 1.0);
    gl_FragData[4] = vec4(smoothness, metalness, pbrEmissive, 1.0); // colortex5
}
