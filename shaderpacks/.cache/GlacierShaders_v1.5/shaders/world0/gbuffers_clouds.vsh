#version 120

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform vec3 sunPosition;
uniform vec3 cameraPosition;
uniform float time; // For cloud movement

varying vec2 texcoord;
varying vec3 cPos;
varying vec3 wPos;
varying vec4 glcolor;
varying vec3 sunDir;
varying vec3 cloudPos;

void main() {
    gl_Position = ftransform();
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    glcolor = gl_Color;

    // Transform vertex position to world space
    vec4 pos = gbufferModelViewInverse * gl_ModelViewMatrix * gl_Vertex;
    cPos = pos.xyz + cameraPosition;
    wPos = pos.xyz;

    // Compute sun direction
    sunDir = normalize(sunPosition - wPos);

    // Cloud movement (animated drift effect)
    float cloudSpeed = 0.02; // Adjust for faster/slower clouds
    cloudPos = wPos + vec3(time * cloudSpeed, 0.0, time * (cloudSpeed * 0.8));

    // Proper transformation for correct rendering
    gl_Position = gl_ProjectionMatrix * gbufferModelView * pos;
}
