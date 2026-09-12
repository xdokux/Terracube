#version 120

#include "/lib/settings.glsl"

uniform mat4 gbufferModelViewInverse;

varying vec3 vWorldDirection;

void main() {
    vec4 viewPosition = gl_ModelViewMatrix * gl_Vertex;
    vWorldDirection = mat3(gbufferModelViewInverse) * viewPosition.xyz;
    gl_Position = gl_ProjectionMatrix * viewPosition;
}
