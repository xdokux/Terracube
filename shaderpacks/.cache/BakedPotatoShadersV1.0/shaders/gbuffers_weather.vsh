#version 120

#include "/lib/settings.glsl"

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform float frameTimeCounter;
uniform float rainStrength;

varying vec2 vTexCoord;
varying vec4 vColor;
varying vec3 vPlayerPosition;

void main() {
    vec4 viewPosition = gl_ModelViewMatrix * gl_Vertex;
    vec3 playerPosition = (gbufferModelViewInverse * viewPosition).xyz;

    float rain = clamp(rainStrength, 0.0, 1.0);
    float heightPhase = playerPosition.y * 0.060;
    float windVariation = sin(frameTimeCounter * 0.72 + heightPhase) * 0.55 +
                          sin(frameTimeCounter * 0.31 + heightPhase * 1.70) * 0.45;
    vec2 windOffset = vec2(0.82, 0.57) * (0.042 + windVariation * 0.018) * rain;
    viewPosition.xyz += mat3(gbufferModelView) * vec3(windOffset.x, 0.0, windOffset.y);

    vPlayerPosition = playerPosition + vec3(windOffset.x, 0.0, windOffset.y);
    vTexCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vColor = gl_Color;
    gl_Position = gl_ProjectionMatrix * viewPosition;
}
