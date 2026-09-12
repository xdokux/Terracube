#version 330 compatibility

#include "/library/distort.glsl"

in vec2 mc_Entity;

out float mask;
out vec2 texcoord;
out vec4 glcolor;

void main() {
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    glcolor = gl_Color;
    
    mask = mc_Entity.x;

    gl_Position = ftransform();
    gl_Position.xyz = distortShadowClipPos(gl_Position.xyz);
}