#version 120 compatibility
#define gbuffers_terrain

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;

varying vec4 color;
varying vec2 texcoord;
varying vec2 lmcoord;

void main()
{
    vec3 position = (gl_ModelViewMatrix * gl_Vertex).xyz;
    position = (gbufferModelViewInverse * vec4(position, 1.0)).xyz;

    gl_Position = gl_ProjectionMatrix * gbufferModelView * vec4(position, 1.0);
    gl_FogFragCoord = length(position);

    color = gl_Color;
    texcoord = gl_MultiTexCoord0.st;
    lmcoord = gl_MultiTexCoord1.st;
}