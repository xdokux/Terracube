#version 330 compatibility

#include "lib/water.glsl"

uniform vec3 cameraPosition;
uniform float frameTimeCounter;
uniform float rainStrength;

varying vec2 texCoord;
varying vec2 lightMapCoord;
varying vec3 normal;
varying vec3 viewPos;
varying vec4 vertexColor;
varying float isLikelyWater;
varying vec2 rippleNormalOffset;

void main() {
    texCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lightMapCoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    normal = normalize(gl_NormalMatrix * gl_Normal);
    vertexColor = gl_Color;

    isLikelyWater = step(vertexColor.b, 0.98) * step(0.3, vertexColor.a) * step(vertexColor.a, 0.9);

    vec4 worldPos = gl_Vertex;
    vec3 absoluteWorldPos = worldPos.xyz + cameraPosition;

    float upFacing = smoothstep(0.3, 0.8, normal.y);
    float waveOffset = waterWaveHeight(absoluteWorldPos.xz, frameTimeCounter) * isLikelyWater * upFacing;
    worldPos.y += waveOffset;

    rippleNormalOffset = rainRippleNormal(absoluteWorldPos.xz, frameTimeCounter, rainStrength) * isLikelyWater * upFacing;

    vec4 position = gl_ModelViewMatrix * worldPos;
    viewPos = position.xyz;
    gl_Position = gl_ProjectionMatrix * position;
}
