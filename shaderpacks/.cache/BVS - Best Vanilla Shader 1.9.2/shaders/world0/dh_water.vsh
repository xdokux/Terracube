#version 130

attribute float mc_Entity;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;

out vec4 color;
out vec2 TexCoords;
out vec2 LightmapCoords;
out vec3 viewSpaceGeoNormal;
out vec3 playerPos;

void main()
{
    playerPos = (gl_ModelViewMatrix * gl_Vertex).xyz;
    playerPos = (gbufferModelViewInverse * vec4(playerPos,1)).xyz;

    gl_Position = gl_ProjectionMatrix * gbufferModelView * vec4(playerPos,1);
    gl_FogFragCoord = length(playerPos);

    vec3 normal = gl_NormalMatrix * gl_Normal;
    float light = min(normal.x * normal.x * 0.6f + normal.y * normal.y * 0.25f * (3.0f + normal.y) + normal.z * normal.z * 0.8f, 1.0f);

    color = gl_Color;
    TexCoords = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	
    LightmapCoords = mat2(gl_TextureMatrix[1]) * gl_MultiTexCoord1.xy;
    LightmapCoords = (LightmapCoords * 33.05f / 32.0f) - (1.05f / 32.0f);
	
	viewSpaceGeoNormal = normal;
}