#version 120

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform vec3 sunPosition;
uniform vec3 cameraPosition;
uniform float time; // For cloud animation

varying vec2 texcoord;
varying vec3 cPos;
varying vec3 wPos;
varying vec4 glcolor;
varying vec3 sunDir;
varying vec3 cloudPos;

void main() {
    // Transform vertex to world space
    vec4 pos = gbufferModelViewInverse * gl_ModelViewMatrix * gl_Vertex;
    wPos = pos.xyz;
    cPos = wPos + cameraPosition;

    // Pass vertex color and UVs
    glcolor = gl_Color;
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;

    // Sun direction for glow in fragment shader
    sunDir = normalize(sunPosition - wPos);

    // Animate clouds with small drift
    float cloudSpeed = 0.02; // Adjust speed here
    cloudPos = wPos + vec3(time * cloudSpeed, 0.0, time * cloudSpeed * 0.8);

    // Final screen-space position
    gl_Position = gbufferProjection * gbufferModelView * pos;
}
