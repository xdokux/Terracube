#version 430 compatibility
#include "/lib/cl/common.glsl"

uniform sampler2D lightmap;
uniform sampler2D gtexture;

in vertex_data {
    vec2 texcoord;
    vec2 lmcoord;
    vec4 glcolor;
    vec3 normal;
    vec3 worldPos;
    flat ivec3 localChunkPos;
} data;

/* RENDERTARGETS: 0,1,2 */
layout(location = 0) out vec4 color;
layout(location = 1) out vec4 lightmapData;
layout(location = 2) out vec4 encodedNormal;

void main() {
    color = texture(gtexture, data.texcoord) * data.glcolor;
    vec2 trueLight = clamp((data.lmcoord - 0.03125) * 1.0666667, 0.0, 1.0);
    lightmapData = vec4(trueLight, 0.0, 1.0);
    encodedNormal = vec4(data.normal * 0.5 + 0.5, 1.0);
    vec4 startLight = texture(lightmap, data.lmcoord);
    color = applyColouredLight(color, startLight, data.worldPos, data.localChunkPos);
}
