#version 330 compatibility

#define FOLIAGE_WAVE_STRENGTH 1.0 // // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]

out float mask;
out float emission;
out vec2 lmcoord;
out vec2 texcoord;
out vec3 normal;
out vec3 wp;
out vec4 glcolor;

in vec2 mc_Entity;
in vec4 at_midBlock;

uniform mat4 gbufferModelViewInverse;
uniform float frameTimeCounter;
uniform vec3 cameraPosition;

void main() {
    gl_Position = ftransform();
    glcolor = gl_Color;

    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    lmcoord = lmcoord / (30.0 / 32.0) - (1.0 / 32.0);

    normal = gl_NormalMatrix * gl_Normal;
    normal = mat3(gbufferModelViewInverse) * normal;

    emission = at_midBlock.w;
    mask = mc_Entity.x;

    vec3 worldPos = gl_Vertex.xyz + cameraPosition;

    if (mask == 1.0 && FOLIAGE_WAVE_STRENGTH > 0.0) {
        float speed = frameTimeCounter * 1.5;

        float skylight = smoothstep(0.1, 0.5, lmcoord.y); 
        
        vec3 displacement = vec3(
            sin(speed + worldPos.x + worldPos.z) * 0.05, 
            sin(speed + worldPos.x * 0.5 + worldPos.z * 0.5) * 0.02, 
            cos(speed + worldPos.x + worldPos.z) * 0.05
        ) * skylight * FOLIAGE_WAVE_STRENGTH;

        gl_Position = gl_Position + gl_ModelViewProjectionMatrix * vec4(displacement, 0.0);
    }
}