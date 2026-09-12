#version 120

// GamesofDev is non chalant
varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 glColor;
varying vec3 normal;

attribute float mc_Entity;
varying float blockId;

attribute vec4 at_tangent;
varying vec3 tangent;
varying vec3 binormal;

uniform vec3 cameraPosition;
uniform float frameTimeCounter;
uniform int worldTime;
uniform float rainStrength;

// Quality setting
#ifndef QUALITY
  #define QUALITY 2
#endif

// Waving disabled on Min quality
#if QUALITY == 1
  #undef WAVING_ENABLED
  #define WAVING_ENABLED 0
#endif

// User Config Defines (Defaults)
#ifndef WAVING_ENABLED
#define WAVING_ENABLED 1
#endif
#define WAVING_SPEED 1.0
#define WAVING_WORLD_SCALE 1.0
#define WAVING_AMOUNT_1 1.0
#define WAVING_AMOUNT_2 1.0
#define WAVING_AMOUNT_3 1.0
#define WAVING_WEATHER_MULT 2.5
#define WAVING_NIGHT_MULT 0.5
#define HEIGHT_BASED_WAVING_ENABLED 1

// Constants
const vec3 windDirection = vec3(1.0, 0.1, 0.3);

// Random/Hash function (GLSL 1.20 compatible - float based)
vec3 hashvec3(float p) {
    vec3 p3 = fract(vec3(p) * vec3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xxy + p3.yzz) * p3.zyx);
}

// Cubic Interpolation
vec3 cubicInterpolate(vec3 y0, vec3 y1, vec3 y2, vec3 y3, float mu) {
   vec3 a0,a1,a2,a3;
   float mu2 = mu*mu;
   a0 = y3 - y2 - y0 + y1;
   a1 = y0 - y1 - a0;
   a2 = y2 - y0;
   a3 = y1;
   return(a0*mu*mu2+a1*mu2+a2*mu+a3);
}

// Calculate waving amount
vec3 getWavingAddition(vec3 localPos) {
    vec3 worldPos = localPos + cameraPosition;
    
    // Calculate time pos based on wind and position
    float timePos = frameTimeCounter + dot(worldPos, windDirection) * WAVING_WORLD_SCALE * 0.2;
    timePos *= WAVING_SPEED * 1.75;
    
    float timePosFloor = floor(timePos);
    
    // Generate random vectors for cubic interpolation
    vec3 pos1 = hashvec3(timePosFloor);
    vec3 pos2 = hashvec3(timePosFloor + 1.0);
    vec3 pos3 = hashvec3(timePosFloor + 2.0);
    vec3 pos4 = hashvec3(timePosFloor + 3.0);
    
    vec3 wavingAmount = cubicInterpolate(pos1, pos2, pos3, pos4, fract(timePos)) - 0.5;
    wavingAmount *= vec3(1.0, 0.2, 1.0) * 0.075; // Logic from user
    
    #if HEIGHT_BASED_WAVING_ENABLED == 1
        const float lowY = 60.0;
        const float highY = 100.0;
        float heightFactor = smoothstep(lowY, highY, worldPos.y);
        wavingAmount *= mix(1.0, 1.75, heightFactor);
    #endif
    
    return wavingAmount;
}

void applyWaving(inout vec3 position, float materialIdValue) {
    // Decode ID (GLSL 1.20 safe - no bitwise)
    // Logic: ((ID >> 10) & 7) >> 1
    // >> 10 equivalent to / 1024
    // & 7 equivalent to % 8
    // >> 1 equivalent to / 2
    
    int matID = int(materialIdValue);
    int encodedData = matID / 1024; 
    int wavingType = (encodedData - (encodedData / 8) * 8) / 2; // Mimic % 8 using division
    
    // If typ 0 or invalid -> return
    if (wavingType == 0) return;
    
    float wavingScale = 0.0;
    if (wavingType == 1) wavingScale = WAVING_AMOUNT_1; // Small plants
    else if (wavingType == 2) wavingScale = WAVING_AMOUNT_2; // Leaves
    else if (wavingType == 3) wavingScale = WAVING_AMOUNT_3; // Crops
    
    // Weather influence
    wavingScale *= 1.0 + rainStrength * (WAVING_WEATHER_MULT - 1.0);
    
    // Night influence calculation
    float dayFactor = 1.0;
    // Simple estimation from worldTime (0-24000)
    // 13000 to 23000 is night
    float time = mod(float(worldTime), 24000.0);
    if (time > 13000.0 && time < 23000.0) dayFactor = 0.0;
    
    float nightMult = mix(WAVING_NIGHT_MULT, 1.0, dayFactor);
    wavingScale *= nightMult;
    
    // Apply
    if (wavingScale > 0.0) {
        position += getWavingAddition(position) * wavingScale;
    }
}

void main() {
    gl_Position = ftransform(); // Default fallback
    
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).st;
    lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).st;
    glColor = gl_Color;
    normal = normalize(gl_NormalMatrix * gl_Normal);
    tangent = normalize(gl_NormalMatrix * at_tangent.xyz);
    binormal = cross(normal, tangent) * at_tangent.w;
    blockId = mc_Entity;
    
    // Process position manually for waving
    vec4 localVertex = gl_Vertex;
    
    // Apply waving
    #if WAVING_ENABLED == 1
    if (mc_Entity > 2000.0) { // Optimize: only check if valid range
        applyWaving(localVertex.xyz, mc_Entity);
    }
    #endif
    
    // Re-calculate position
    gl_Position = gl_ModelViewProjectionMatrix * localVertex;
}
