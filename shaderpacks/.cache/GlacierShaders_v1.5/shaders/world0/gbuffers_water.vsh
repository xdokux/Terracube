#version 120

#define lerp(x, y, a) (x * (1.0 - a) + y * a) // Custom mix function

uniform vec3 cameraPosition;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform int worldTime;
uniform float frameTimeCounter;

attribute vec4 mc_Entity;

varying vec2 lmcoord;
varying vec2 texcoord;
varying vec4 glcolor;
varying vec3 cPos;
varying vec3 wPos;
varying float waterHeight;
varying vec2 uv1;
varying float waterFlag;
varying vec3 normal;
varying vec4 positionInViewCoord;

void main() {
    // Transform vertex position to view coordinates
    positionInViewCoord = gl_ModelViewMatrix * gl_Vertex;
    gl_Position = gbufferProjection * positionInViewCoord;

    // Texture coordinates
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;

    // Vertex color and normal
    glcolor = gl_Color;
    normal = gl_NormalMatrix * gl_Normal;

    // Initialize water flag
    waterFlag = 0.0;

    // Calculate world and camera-relative positions
    cPos = (gbufferModelViewInverse * gl_ModelViewMatrix * gl_Vertex).xyz + cameraPosition;
    wPos = (gbufferModelViewInverse * (gl_ModelViewMatrix * gl_Vertex)).xyz;

    // Check if the entity is water (mc_Entity.x == 8.0 or 9.0)
    if (mc_Entity.x == 8.0 || mc_Entity.x == 9.0) {
        waterFlag = 1.0;

        // Apply water wave effect (commented out for now)
        // float waterWave = sin(noise(frameTimeCounter + (cPos.xz + cPos.xy + cPos.xz + cPos.xx + cPos.yy + cPos.zz) * 0.2) + 
        //                   noise(frameTimeCounter + (cPos.xz + cPos.xy + cPos.xz + cPos.xx + cPos.yy + cPos.zz) * 0.2)) * 2.0;
        // gl_Position.y -= waterWave * 0.2; // Adjust water height

        uv1 = gl_MultiTexCoord1.xy; // Torch light level
    }

    // waterHeight = waterWave; // Uncomment if using waterWave
}