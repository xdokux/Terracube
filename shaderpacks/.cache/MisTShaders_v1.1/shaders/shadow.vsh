#version 120

//Distort
vec2 DistortPosition(in vec2 position){
    float CenterDistance = length(position);
    float DistortionFactor = mix(1.0f, CenterDistance, 0.9f);
    return position / DistortionFactor;
}

varying vec2 TexCoords;
varying vec4 Color;

void main(){
    gl_Position    = ftransform();
    gl_Position.xy = DistortPosition(gl_Position.xy);
    TexCoords = gl_MultiTexCoord0.st;
    Color = gl_Color;
}
