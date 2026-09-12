#version 430 compatibility
#define VERTEX
#include "/lib/cl/common.glsl"

uniform float frameTimeCounter;
in vec3 at_midBlock;
in ivec2 mc_Entity;

out vertex_data {
    vec2 texcoord;
    vec2 lmcoord;
    vec4 glcolor;
    vec3 normal;
    vec3 worldPos;
    flat ivec3 localChunkPos;
} data;

void main() {
    vec4 pos = gl_Vertex;
    float speed = frameTimeCounter * 0.6;
    float wave = sin(pos.x * 0.12 + speed) * 0.015 +
                 cos(pos.z * 0.15 + speed * 0.8) * 0.01;
    pos.y += wave;
    gl_Position = gl_ModelViewProjectionMatrix * pos;
    data.texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    data.lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    data.glcolor = gl_Color;
    float dx = 0.12 * cos(pos.x * 0.12 + speed) * 0.015;
    float dz = -0.15 * sin(pos.z * 0.15 + speed * 0.8) * 0.01;
    vec3 waveNormal = normalize(vec3(-dx, 1.0, -dz));
    data.normal = gl_NormalMatrix * waveNormal;
    data.normal = mat3(gbufferModelViewInverse) * data.normal;
    data.worldPos = modelToWorldSpace(gl_Vertex.xyz);
    data.localChunkPos = blockPosToChunkPos(blockPosToLocalPos(worldPosToBlockPos(data.worldPos, at_midBlock)));
    lightCheck(at_midBlock, mc_Entity);
}
