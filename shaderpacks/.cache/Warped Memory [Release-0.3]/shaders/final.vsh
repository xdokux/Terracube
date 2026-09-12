#version 120

// Massive atribute
attribute vec4 mc_Entity;
attribute vec4 mc_Vertex;
attribute vec2 mc_TexCoord0;

// Input data for fragment shader
varying vec2 vTexCoord;
varying vec4 vPosition;

uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
varying vec4 shadowPos;

void main()
{
    gl_Position = gl_ModelViewProjectionMatrix * mc_Vertex;
    vTexCoord = mc_TexCoord0;
    vPosition = gl_Position;

    shadowPos = shadowProjection * shadowModelView * mc_Vertex;
}