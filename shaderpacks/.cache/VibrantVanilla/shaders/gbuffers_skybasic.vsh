#version 120
varying vec4 glcolor;
void main() {
    gl_Position = gl_ModelViewProjectionMatrix * gl_Vertex;
    glcolor = gl_Color;
}
