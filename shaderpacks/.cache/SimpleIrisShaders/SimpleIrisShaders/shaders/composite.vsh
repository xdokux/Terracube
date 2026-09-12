/*
    composite.vsh
    ---------------------------------------------------------------
    Pipeline stage: COMPOSITE (post-processing, full screen)
    Iris/OptiFine draws a single full-screen triangle for composite
    stages automatically - this shader just needs to forward the
    texture coordinate.
    ---------------------------------------------------------------
*/
#version 330 compatibility

varying vec2 texCoord;

void main() {
    texCoord = gl_MultiTexCoord0.xy;
    gl_Position = ftransform();
}
