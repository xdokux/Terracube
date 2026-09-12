#version 120

// GamesofDev is non chalant
varying vec2 texcoord;

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex4;
uniform sampler2D colortex5;
uniform sampler2D depthtex0;  // Depth (with translucent)
uniform sampler2D depthtex1;  // Depth (without translucent = opaque only)

uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;

uniform vec3 shadowLightPosition;
uniform vec3 sunPosition;
uniform vec3 cameraPosition;

uniform int worldTime;
uniform float viewWidth;
uniform float viewHeight;
uniform int isEyeInWater;
uniform float frameTimeCounter;
uniform float near;
uniform float far;

/* DRAWBUFFERS:0 */

// ═══════════════════════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════

#define WATER_REFRACT_IOR 1.333
#define GLASS_REFRACT_IOR 1.45
#define PI 3.14159265

// Quality setting
#ifndef QUALITY
  #define QUALITY 2
#endif

// Quality-dependent SSR parameters
#if QUALITY == 1
  #define SSR_ENABLED 0
  #define SSR_STEPS 0
  #define SSR_REFINE 0
#elif QUALITY == 3
  #define SSR_ENABLED 1
  #define SSR_STEPS 64
  #define SSR_REFINE 8
  #define ENABLE_CHROMATIC_ABERRATION 1
#else
  #define SSR_ENABLED 1
  #define SSR_STEPS 32
  #define SSR_REFINE 4
#endif

// ═══════════════════════════════════════════════════════════════════════════
// UTILITY FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════

vec3 getViewPosition(vec2 coord, float depth) {
    vec4 clipPos = vec4(coord * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 viewPos = gbufferProjectionInverse * clipPos;
    return viewPos.xyz / viewPos.w;
}

float linearizeDepth(float depth) {
    return (2.0 * near * far) / (far + near - (depth * 2.0 - 1.0) * (far - near));
}

// Convert view position to screen coordinates
vec3 viewToScreen(vec3 vPos) {
    vec4 clipPos = gbufferProjection * vec4(vPos, 1.0);
    return (clipPos.xyz / clipPos.w) * 0.5 + 0.5;
}

// Physically accurate dielectric Fresnel
float FresnelDielectricN(float cosTheta, float n) {
    float cosR = n * n + cosTheta * cosTheta - 1.0;
    if (cosR < 0.0) return 1.0;

    cosR = sqrt(cosR);
    float a = n * cosTheta;
    float b = n * cosR;
    float r1 = (a - cosR) / (a + cosR);
    float r2 = (b - cosTheta) / (b + cosTheta);
    return clamp(0.5 * (r1 * r1 + r2 * r2), 0.0, 1.0);
}

// Fast refraction direction
vec3 fastRefract(vec3 dir, vec3 N, float eta) {
    float NdotD = dot(N, dir);
    float k = 1.0 - eta * eta * (1.0 - NdotD * NdotD);
    if (k < 0.0) return vec3(0.0);
    return dir * eta - N * (sqrt(k) + NdotD * eta);
}

// Interleaved gradient noise
float interleavedGradientNoise(vec2 coord) {
    vec3 magic = vec3(0.06711056, 0.00583715, 52.9829189);
    return fract(magic.z * fract(dot(coord, magic.xy)));
}

// ═══════════════════════════════════════════════════════════════════════════
// SCREEN SPACE REFLECTIONS — reads from colortex4 (lit scene)
// ═══════════════════════════════════════════════════════════════════════════

vec4 traceSSR(vec3 vPos, vec3 reflectDir, float dither) {
    const int maxSteps = SSR_STEPS;
    const int refinementSteps = SSR_REFINE;
    
    float stepSize = 0.5;
    vec3 rayPos = vPos;
    vec3 rayStep = reflectDir * stepSize;
    
    rayPos += rayStep * dither;
    
    bool hit = false;
    vec3 hitScreenPos = vec3(0.0);
    
    for (int i = 0; i < maxSteps; i++) {
        rayPos += rayStep;
        
        vec3 screenPos = viewToScreen(rayPos);
        
        if (screenPos.x < 0.0 || screenPos.x > 1.0 ||
            screenPos.y < 0.0 || screenPos.y > 1.0 ||
            screenPos.z < 0.0 || screenPos.z > 1.0) {
            break;
        }
        
        float sampledDepth = texture2D(depthtex0, screenPos.xy).r;
        
        float depthDiff = screenPos.z - sampledDepth;
        if (depthDiff > 0.0 && depthDiff < stepSize * 0.1) {
            hit = true;
            hitScreenPos = screenPos;
            
            // Binary search refinement
            vec3 backStep = rayStep * 0.5;
            for (int j = 0; j < refinementSteps; j++) {
                rayPos -= backStep;
                backStep *= 0.5;
                
                screenPos = viewToScreen(rayPos);
                sampledDepth = texture2D(depthtex0, screenPos.xy).r;
                if (screenPos.z > sampledDepth) {
                    rayPos -= backStep;
                } else {
                    rayPos += backStep;
                }
            }
            hitScreenPos = viewToScreen(rayPos);
            break;
        }
        
        rayStep *= 1.05;
    }
    
    if (hit) {
        // Read from colortex4 — the FULLY LIT scene!
        vec3 hitColor = texture2D(colortex4, hitScreenPos.xy).rgb;
        
        // Edge fading
        vec2 edgeFade = smoothstep(vec2(0.0), vec2(0.05), hitScreenPos.xy) *
                        (1.0 - smoothstep(vec2(0.95), vec2(1.0), hitScreenPos.xy));
        float fade = edgeFade.x * edgeFade.y;
        
        return vec4(hitColor, fade);
    }
    
    return vec4(0.0);
}

// ═══════════════════════════════════════════════════════════════════════════
// SKY REFLECTION FALLBACK
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
    vec3 sunDir = normalize(mat3(gbufferModelViewInverse) * normalize(shadowLightPosition));
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
// MAIN
// ═══════════════════════════════════════════════════════════════════════════

void main() {
    float depth = texture2D(depthtex0, texcoord).r;
    float depthSolid = texture2D(depthtex1, texcoord).r;
    
    vec3 litScene = texture2D(colortex0, texcoord).rgb;
    vec4 pbrData = texture2D(colortex5, texcoord);
    float smoothness = pbrData.r;
    float metalness = pbrData.g;
    
    bool isTranslucent = (depth != depthSolid);
    bool isPBR = (smoothness > 0.01 || metalness > 0.01);
    
    // Check if this is actually a reflective/refractive material (water/glass/ice)
    float materialId = texture2D(colortex2, texcoord).g;
    bool isRefractiveMaterial = (materialId > 0.7); // water=0.8, glass=0.85, stained=0.9, ice=0.95
    
    // Pass through sky or non-PBR solid blocks
    if (depth >= 1.0 || (!isTranslucent && !isPBR)) {
        gl_FragData[0] = vec4(litScene, 1.0);
        return;
    }
    
    // Pass through non-refractive translucent blocks (like entities/hands with transparency)
    if (isTranslucent && !isRefractiveMaterial && !isPBR) {
        gl_FragData[0] = vec4(litScene, 1.0);
        return;
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // TRANSLUCENT PIXEL — Apply Refraction + Reflection
    // ═══════════════════════════════════════════════════════════════════════
    
    vec4 albedoData = texture2D(colortex0, texcoord);
    vec4 normalData = texture2D(colortex1, texcoord);
    vec4 lightData  = texture2D(colortex2, texcoord);
    
    vec3 albedo = albedoData.rgb;
    float alpha = albedoData.a;
    vec3 normal = normalize(normalData.rgb * 2.0 - 1.0);
    float skyLight = normalData.a;
    // materialId already declared above
    
    // Identify material type from materialId
    bool isWater       = abs(materialId - 0.8) < 0.03;
    bool isGlass       = abs(materialId - 0.85) < 0.03;
    bool isStainedGlass = abs(materialId - 0.9) < 0.03;
    bool isIce         = abs(materialId - 0.95) < 0.03;
    
    // Choose IOR
    float ior = GLASS_REFRACT_IOR;
    if (isWater) ior = WATER_REFRACT_IOR;
    if (isIce) ior = 1.31;
    
    vec3 viewPos = getViewPosition(texcoord, depth);
    vec3 viewDir = normalize(viewPos);
    vec3 N = normal;
    float NdotV = max(dot(N, -viewDir), 0.001);
    
    // Time of day (worldTime-based, camera-independent)
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
    
    // ═══════════════════════════════════════════════════════════════════════
    // REFRACTION — read scene behind glass from colortex4 (fully lit)
    // ═══════════════════════════════════════════════════════════════════════
    
    vec3 refractedScene = texture2D(colortex4, texcoord).rgb; // Default: straight through
    
    bool hasRefraction = isTranslucent && (isGlass || isStainedGlass || isIce) && isEyeInWater == 0;
    
    if (hasRefraction) {
        // Normal-based offset refraction
        float surfaceLinear = linearizeDepth(depth);
        float behindLinear = linearizeDepth(depthSolid);
        float refractionDepth = clamp(behindLinear - surfaceLinear, 0.0, 2.0);
        
        vec2 refractOffset = N.xy * 0.03 * clamp(refractionDepth, 0.0, 1.0);
        vec2 refractCoord = clamp(texcoord + refractOffset, vec2(0.001), vec2(0.999));
        
        // Validate: don't sample in front of glass surface
        float refractedDepth = texture2D(depthtex1, refractCoord).r;
        if (refractedDepth > depth) {
            #ifdef ENABLE_CHROMATIC_ABERRATION
                // Ultra: chromatic aberration through glass
                vec2 caOffset = refractOffset * 0.3;
                vec2 coordR = clamp(refractCoord + caOffset, vec2(0.001), vec2(0.999));
                vec2 coordB = clamp(refractCoord - caOffset, vec2(0.001), vec2(0.999));
                refractedScene.r = texture2D(colortex4, coordR).r;
                refractedScene.g = texture2D(colortex4, refractCoord).g;
                refractedScene.b = texture2D(colortex4, coordB).b;
            #else
                refractedScene = texture2D(colortex4, refractCoord).rgb;
            #endif
        }
        
        // Colored glass absorption
        if (isStainedGlass) {
            vec3 absorption = pow(albedo, vec3(0.5)) * 1.2;
            refractedScene *= absorption;
        }
        
        // Ice tint
        if (isIce) {
            refractedScene *= vec3(0.85, 0.92, 1.0);
        }
    }
    
    // For water, read the scene behind too
    if (isWater && isEyeInWater == 0) {
        refractedScene = texture2D(colortex4, texcoord).rgb;
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // REFLECTIONS — SSR + sky fallback
    // ═══════════════════════════════════════════════════════════════════════
    
    vec3 rayDir = reflect(viewDir, N);
    float NdotL = dot(N, rayDir);
    
    vec3 reflection = vec3(0.0);
    float reflectionStrength = 0.0;
    
    #if SSR_ENABLED == 1
    if (NdotL > 0.001) {
        float dither = interleavedGradientNoise(gl_FragCoord.xy + frameTimeCounter * 100.0);
        
        vec4 ssrResult = traceSSR(viewPos, rayDir, dither);
        
        vec3 worldReflDir = mat3(gbufferModelViewInverse) * rayDir;
        float skylightCubed = skyLight * skyLight * skyLight;
        
        if (ssrResult.a > 0.01) {
            vec3 skyFallback = getSkyReflection(worldReflDir, dayFactor);
            if (isEyeInWater == 0) {
                reflection = mix(skyFallback * skylightCubed, ssrResult.rgb, ssrResult.a);
            } else {
                reflection = mix(vec3(0.05, 0.7, 1.0) * 0.3, ssrResult.rgb, ssrResult.a);
            }
        } else {
            if (isEyeInWater == 0) {
                reflection = getSkyReflection(worldReflDir, dayFactor) * skylightCubed;
            } else {
                reflection = vec3(0.05, 0.7, 1.0) * 0.25;
            }
        }
        
        reflectionStrength = 1.0;
    }
    #else
    // Min quality: sky reflection only, no SSR
    if (NdotL > 0.001) {
        vec3 worldReflDir = mat3(gbufferModelViewInverse) * rayDir;
        float skylightCubed = skyLight * skyLight * skyLight;
        if (isEyeInWater == 0) {
            reflection = getSkyReflection(worldReflDir, dayFactor) * skylightCubed;
        } else {
            reflection = vec3(0.05, 0.7, 1.0) * 0.25;
        }
        reflectionStrength = 1.0;
    }
    #endif
    
    // ═══════════════════════════════════════════════════════════════════════
    // FRESNEL BLEND
    // ═══════════════════════════════════════════════════════════════════════
    
    float fresnel;
    if (isEyeInWater == 1) {
        fresnel = FresnelDielectricN(NdotV, 1.0 / WATER_REFRACT_IOR);
    } else {
        fresnel = FresnelDielectricN(NdotV, ior);
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // FINAL COMPOSITING
    // ═══════════════════════════════════════════════════════════════════════
    
    vec3 finalColor;
    
    if (!isTranslucent && isPBR) {
        // Opaque PBR material: Lit scene is the base, just add PBR reflections
        // Approximated F0 using base color from lit scene (which is wrong under light, but good enough for SSR blending)
        vec3 F0 = mix(vec3(0.04), litScene, metalness);
        vec3 F = F0 + (max(vec3(1.0 - (1.0 - smoothness)), F0) - F0) * pow(clamp(1.0 - NdotV, 0.0, 1.0), 5.0);
        
        // Specular occlusion in shadows
        // Remove skyVisibility damping to allow indoor reflections (e.g. from torches/lanterns)
        
        // Add SSR reflection on top
        finalColor = litScene + reflection * F * (smoothness * 2.0);
        
    } else if (isWater) {
        // Water: murky tint + reflection
        finalColor = refractedScene * (1.0 - fresnel) + reflection * fresnel;
    } else if (reflectionStrength > 0.0) {
        // Glass/Ice: refraction + reflection via Fresnel
        finalColor = refractedScene * (1.0 - fresnel) + reflection * fresnel;
    } else {
        finalColor = refractedScene;
    }
    
    gl_FragData[0] = vec4(finalColor, 1.0);
}
