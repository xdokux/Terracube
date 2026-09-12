#version 430 compatibility
#define VERTEX
#include "/lib/cl/common.glsl"

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
    gl_Position = ftransform();
    data.texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    data.lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    data.glcolor = gl_Color;
    data.normal = gl_NormalMatrix * gl_Normal;
    data.normal = mat3(gbufferModelViewInverse) * data.normal;
    data.worldPos = modelToWorldSpace(gl_Vertex.xyz);
    data.localChunkPos = blockPosToChunkPos(blockPosToLocalPos(worldPosToBlockPos(data.worldPos, at_midBlock)));
    lightCheck(at_midBlock, mc_Entity);
}
