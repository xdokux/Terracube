#version 120

varying vec2 texcoord;
varying vec4 glcolor;

void main() {
    // Calculates the 3D position of the block
    gl_Position = ftransform();
    
    // Grabs the texture coordinates (so wood looks like wood)
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    
    // Grabs the block's lighting and color
    glcolor = gl_Color;
}