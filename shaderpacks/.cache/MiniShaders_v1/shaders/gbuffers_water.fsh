#version 120

// GamesofDev is non chalant
varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 glColor;
varying vec3 normal;
varying vec3 worldPos;
varying vec3 viewPos;
varying float blockId;

uniform sampler2D texture;
uniform sampler2D specular;
uniform sampler2D normals;

uniform int isEyeInWater;
uniform float frameTimeCounter;

varying vec3 tangent;
varying vec3 binormal;

/* DRAWBUFFERS:0125 */

// ═══════════════════════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════

#define WATER_TINT vec3(0.05, 0.15, 0.25)

// ═══════════════════════════════════════════════════════════════════════════
// MAIN
// ═══════════════════════════════════════════════════════════════════════════

void main() {
    // Material detection
    bool isWater = blockId > 9999.5 && blockId < 10000.5;
    bool isGlass = abs(blockId - 10020.0) < 0.5;
    bool isStainedGlass = abs(blockId - 10021.0) < 0.5;
    bool isIce = abs(blockId - 10022.0) < 0.5;
    bool isPortal = abs(blockId - 10023.0) < 0.5;
    
    // Base color from texture
    vec4 albedo = texture2D(texture, texcoord) * glColor;
    
    // Alpha test
    if (albedo.a < 0.01) discard;
    
    vec3 N = normalize(normal);
    
    // ═══════════════════════════════════════════════════════════════════════
    // MATERIAL OUTPUT
    // ═══════════════════════════════════════════════════════════════════════
    
    vec3 finalColor;
    float finalAlpha;
    
    // Material ID for composite1 to identify material type:
    // 0.8 = water, 0.85 = glass, 0.9 = stained glass, 0.95 = ice, 0.75 = portal
    float materialId = 0.0;
    
    if (isWater) {
        vec3 tint = WATER_TINT * (lmcoord.y * 0.5 + 0.5);
        finalColor = mix(albedo.rgb, tint, 0.6);
        finalAlpha = 0.85;
        materialId = 0.8;
    } else if (isPortal) {
        // Nether portal: vibrant purple with pulsing glow
        vec3 portalColor = albedo.rgb;
        // Enhance purple tones
        float pulse = sin(frameTimeCounter * 2.0) * 0.15 + 0.85;
        portalColor = max(portalColor, vec3(0.3, 0.05, 0.5)) * pulse;
        finalColor = portalColor;
        finalAlpha = 0.8;
        materialId = 0.75;
    } else if (isStainedGlass) {
        finalColor = albedo.rgb;
        finalAlpha = albedo.a * 0.9;
        materialId = 0.9;
    } else if (isIce) {
        vec3 iceTint = vec3(0.85, 0.92, 1.0);
        finalColor = albedo.rgb * iceTint;
        finalAlpha = 0.92;
        materialId = 0.95;
    } else if (isGlass) {
        finalColor = albedo.rgb;
        finalAlpha = 0.3;
        materialId = 0.85;
    } else {
        // Unknown translucent blocks — render normally (don't discard!)
        finalColor = albedo.rgb;
        finalAlpha = albedo.a;
        materialId = 0.0;
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
    
    vec4 normData = texture2D(normals, texcoord);
    if (length(normData.rgb) > 0.01) {
        vec3 normalMap = normData.rgb * 2.0 - 1.0;
        mat3 TBN = mat3(tangent, binormal, N);
        worldNormal = normalize(TBN * normalMap);
    }
    
    // Output to G-buffers
    gl_FragData[0] = vec4(finalColor, finalAlpha);           // colortex0: Albedo + alpha
    gl_FragData[1] = vec4(worldNormal * 0.5 + 0.5, lmcoord.y);       // colortex1: Normal + skylight
    gl_FragData[2] = vec4(lmcoord.x, materialId, 0.0, 1.0); // colortex2: blockLight + materialId
    gl_FragData[3] = vec4(smoothness, metalness, pbrEmissive, 1.0); // colortex5: PBR Data
}
