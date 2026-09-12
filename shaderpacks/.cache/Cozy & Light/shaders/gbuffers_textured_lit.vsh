#version 330 compatibility

uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform float frameTimeCounter; // For waving animation

in vec3 vaPosition;
in vec3 vaNormal;
in vec4 mc_Entity; // Needed to check block/entity type

out vec2 lmcoord;
out vec2 texcoord;
out vec4 glcolor;
out vec4 shadowPos;
out vec3 vertexPosition;
out float depth;
out vec3 normal;

#include "/distort.glsl"
#include "lib.glsl"

void main() {
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    glcolor = gl_Color;
    vertexPosition = gl_Vertex.xyz;
    depth = length(gl_ModelViewMatrix * gl_Vertex);
    normal = gl_Normal;

    float lightDot = dot(normalize(shadowLightPosition), normalize(gl_NormalMatrix * gl_Normal));

    vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;

    // ========================
    // Waving effect (foliage only)
    // ========================
    // mc_Entity.x values (8, 9, 10) are common for grass/leaves/crops in OptiFine/Iris
    if (mc_Entity.x == 8.0 || mc_Entity.x == 9.0 || mc_Entity.x == 10.0) {
        float waveSpeed = 2.0;   // speed of sway
        float waveSize  = 0.05;  // strength of sway

        // Smooth waving based on world position
        float wave = sin(vaPosition.x * 0.5 + frameTimeCounter * waveSpeed) * waveSize;
        wave += cos(vaPosition.z * 0.5 + frameTimeCounter * waveSpeed) * waveSize;

        viewPos.y += wave; // apply sway to Y position
    }
    // ========================

    if (lightDot > 0.0) { //vertex is facing towards the sun
        vec4 playerPos = gbufferModelViewInverse * viewPos;
        shadowPos = shadowProjection * (shadowModelView * playerPos); //convert to shadow ndc space.
        float bias = computeBias(shadowPos.xyz);
        shadowPos.xyz = distort(shadowPos.xyz); //apply shadow distortion
        shadowPos.xyz = shadowPos.xyz * 0.5 + 0.5; //convert from -1 ~ +1 to 0 ~ 1

        #ifdef NORMAL_BIAS
            vec4 shadowNormal = shadowProjection * vec4(mat3(shadowModelView) * (mat3(gbufferModelViewInverse) * (gl_NormalMatrix * gl_Normal)), 1.0);
            shadowPos.xyz += shadowNormal.xyz / shadowNormal.w * bias;
        #else
            shadowPos.z -= bias / abs(lightDot);
        #endif
    }
    shadowPos.w = lightDot;

    gl_Position = gl_ProjectionMatrix * viewPos;
}
