#include "/lib/all_the_libs.glsl"
#include "/global/lighting.vsh"

// --- PBR OUTPUTS ---
attribute vec4 at_tangent; 

// These variables send data to the Fragment Shader
varying vec4 vTangent; 
varying vec3 vViewPos;

// -------------------

void main() {
    // 1. Run Standard Lighting 
    // This calculates 'Normal', 'glcolor', and 'ViewPos' automatically.
    init_generic();

    vec3 currentViewPos = ViewPos; 
    
    // 3. Base Position Calculation
    vec4 position = gl_ProjectionMatrix * vec4(currentViewPos, 1.0);

    #ifdef WAVY_PLANTS
    if (currentViewPos.z > -64.0) {
        vec3 worldPos = to_player_pos(currentViewPos) + cameraPosition;
        
        // --- WAVING LOGIC ---
        vec3 wavePos = worldPos / WAVE_SIZE + (frameTimeCounter * WAVE_SPEED);
        wavePos = sin(wavePos);
        float noise = wavePos.x * wavePos.y * wavePos.z;
        noise *= (WAVE_AMPLITUDE + rainStrength * 0.1);

        vec3 offset = vec3(0.0);
        bool isWaving = false;

        #ifdef WAVE_LEAVES
        if (material == 10003) {
            offset.x += noise / 2.0; offset.z -= noise / 2.0; offset.y -= noise / 2.0;
            isWaving = true;
        } 
        #endif
        
        if (!isWaving) {
            if (material == 10004 && gl_MultiTexCoord0.t < mc_midTexCoord.t) { offset += noise; isWaving = true; }
            else if (material == 10005 && gl_MultiTexCoord0.t < mc_midTexCoord.t) { offset += noise / 2.0; isWaving = true; }
            else if (material == 10006) {
                 if (gl_MultiTexCoord0.t > mc_midTexCoord.t) offset += noise / 2.0; else offset += noise;
                 isWaving = true;
            }
        }

        // Apply Wave Offset
        if (isWaving) {
            worldPos += offset - cameraPosition;
            
            // Recalculate ViewPos so the lighting/POM moves WITH the plant
            currentViewPos = mat3(gbufferModelView) * worldPos; 
            
            // Recalculate Final Screen Position
            position = gl_ProjectionMatrix * vec4(currentViewPos, 1.0);
        }
    }
    #endif

    gl_Position = position;

    // 4. SEND DATA TO FRAGMENT SHADER
    vViewPos = currentViewPos; // <--- This ensures the .fsh receives the data

    if (at_tangent.w != 0.0) {
        // Provided by the resource pack
        vTangent = vec4(normalize(gl_NormalMatrix * at_tangent.xyz), at_tangent.w);
    } else {
        // Fallback: Calculate in Object Space first
        vec3 t = cross(gl_Normal, vec3(0.0, 1.0, 0.0));
        
        // If the normal is pointing straight up/down, use the X axis instead
        if (length(t) < 0.001) {
            t = cross(gl_Normal, vec3(1.0, 0.0, 0.0));
        }
        
        // Now transform the final calculated tangent into View Space
        t = normalize(gl_NormalMatrix * t);
        
        // Standard handedness fallback is 1.0
        vTangent = vec4(t, 1.0);
    }

    #if TAA_MODE >= 2
    gl_Position.xy += taaJitter * gl_Position.w;
    #endif
}