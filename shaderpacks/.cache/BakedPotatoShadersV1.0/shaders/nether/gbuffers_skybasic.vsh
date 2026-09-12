#version 120

#include "/lib/settings.glsl"

uniform mat4 gbufferModelViewInverse;

varying vec4 vColor;
varying vec3 vWorldDirection;

void main() {
    vec4 viewPosition = gl_ModelViewMatrix * gl_Vertex;
    vWorldDirection = normalize(mat3(gbufferModelViewInverse) * viewPosition.xyz);
    vColor = gl_Color;
    gl_Position = gl_ProjectionMatrix * viewPosition;
}
