#include "/lib/all_the_libs.glsl"
#include "/global/lighting.vsh"

varying mat3 TBN;
attribute vec4 at_tangent;
varying vec3 finalNormal;

// --- SAFETY FUNCTION ---
// This prevents "Black Screen" crashes by stopping division by zero
vec3 safe_normalize(vec3 v) {
    float len = length(v);
    // If the vector is too small (near zero), return a safe default "UP" vector
    if (len < 0.0001) return vec3(0.0, 1.0, 0.0);
    return v / len;
}

void main() {
    init_generic();

    // 1. Start with a safe default
    vec3 computedNormal = vec3(0.0, 1.0, 0.0);
    if (length(Normal) > 0.001) computedNormal = Normal;

    #if WATER_TEXTURE_MODE == 1 || WATER_TEXTURE_MODE == 2
    if(material == 10002) {
        const vec4 BaseColor = vec4(f_WATER_RED, f_WATER_GREEN, f_WATER_BLUE, f_WATER_ALPHA);
        glcolor.rgb = mix_preserve_c1lum(BaseColor.rgb, glcolor.rgb, f_BIOME_WATER_CONTRIBUTION);
        glcolor.rgb = to_linear(glcolor.rgb);
        glcolor.a = BaseColor.a;
    }
    #else
    glcolor.rgb = to_linear(glcolor.rgb);
    #endif

    #ifdef WAVY_PLANTS
    if (ViewPos.z > -64 && material == 10002) {
        vec3 WorldPos = to_player_pos(ViewPos);
        WorldPos += cameraPosition;
        
        // --- NOSTALGIC WAVE SETTINGS ---
        const int WAVE_COUNT = 5;
        float amplitudes[WAVE_COUNT] = float[](0.007, 0.008, 0.006, 0.005, 0.0065);
        float wavelengths[WAVE_COUNT] = float[](1.2, 1.5, 1.6, 1.0, 1.5);
        vec2 directions[WAVE_COUNT] = vec2[](
            safe_normalize(vec3(1.0, 0.0, 0.3)).xz,
            safe_normalize(vec3(0.3, 0.0, 1.0)).xz,
            safe_normalize(vec3(-0.7, 0.0, 0.2)).xz,
            safe_normalize(vec3(0.8, 0.0, -0.3)).xz,
            safe_normalize(vec3(-0.5, 0.0, -0.6)).xz
        );

        vec3 nSum = vec3(0.0);
        float choppiness = 0.5;

        for (int i = 0; i < WAVE_COUNT; i++) {
            float k = 3.0 * 3.14159 / wavelengths[i];
            float phase = dot(directions[i], WorldPos.xz) * k + (frameTimeCounter * 2.2);
            float A = amplitudes[i];
            
            float c = cos(phase);
            float s = sin(phase);
            float wa = k * A; 

            WorldPos.x += directions[i].x * A * c * choppiness;
            WorldPos.z += directions[i].y * A * c * choppiness;
            WorldPos.y += A * s;

            nSum.x -= directions[i].x * wa * c * choppiness;
            nSum.z -= directions[i].y * wa * c * choppiness;
            nSum.y -= wa * s * choppiness; 
        }

        WorldPos -= cameraPosition;
        WorldPos = mat3(gbufferModelView) * WorldPos;
        gl_Position = gl_ProjectionMatrix * vec4(WorldPos, 1);
        
        // Calculate Wave Normal
        vec3 worldWaveNormal = vec3(nSum.x, 1.0 + nSum.y, nSum.z);
        // SAFETY: Use safe_normalize here
        worldWaveNormal = safe_normalize(worldWaveNormal);

        // Transform to View Space
        computedNormal = mat3(gbufferModelView) * worldWaveNormal;
        computedNormal = safe_normalize(computedNormal);
    }
    #endif

    // 2. Update Global Variable
    finalNormal = computedNormal;

    // 3. Robust TBN Calculation (The main cause of black screens)
    vec3 tangent = gbufferModelView[0].xyz;
    
    // SAFETY: If tangent is broken, force a default
    if (length(tangent) < 0.001) tangent = vec3(1.0, 0.0, 0.0);
    else tangent = safe_normalize(tangent);

    // Gram-Schmidt process
    vec3 tangentSub = computedNormal * dot(tangent, computedNormal);
    vec3 newTangent = tangent - tangentSub;
    
    // SAFETY: If subtraction resulted in zero vector (tangent was parallel to normal)
    if (length(newTangent) < 0.001) {
        // Fallback: Just use a generic perpendicular vector
        vec3 fallback = cross(computedNormal, vec3(0.0, 1.0, 0.0));
        if (length(fallback) < 0.001) fallback = cross(computedNormal, vec3(1.0, 0.0, 0.0));
        tangent = safe_normalize(fallback);
    } else {
        tangent = safe_normalize(newTangent);
    }

    vec3 binormal = cross(computedNormal, tangent);
    // SAFETY: One last check on binormal
    binormal = safe_normalize(binormal);
    
    TBN = mat3(tangent, binormal, computedNormal);

    #if TAA_MODE >= 2
    gl_Position.xy += taaJitter * gl_Position.w;
    #endif
}