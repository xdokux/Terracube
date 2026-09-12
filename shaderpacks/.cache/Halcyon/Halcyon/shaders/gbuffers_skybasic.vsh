#version 120

varying vec4 vertexColor;
varying vec3 viewDir;

void main() {
    gl_Position = gl_ProjectionMatrix * gl_ModelViewMatrix * gl_Vertex;
    vertexColor = gl_Color;

    // w=0 drops translation - the sky dome is centered on the camera, so this
    // rotate-only transform puts viewDir into the same view space that
    // sunPosition/upPosition/shadowLightPosition are already given in.
    viewDir = normalize((gl_ModelViewMatrix * vec4(gl_Vertex.xyz, 0.0)).xyz);
}
