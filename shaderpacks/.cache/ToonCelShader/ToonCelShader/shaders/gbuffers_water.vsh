#version 330 compatibility

uniform float frameTimeCounter;
uniform vec3 cameraPosition;

varying vec2 texCoord;
varying vec2 lightMapCoord;
varying vec3 normal;
varying vec3 viewPos;
varying vec4 vertexColor;
varying float isLikelyWater;

void main() {
    texCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lightMapCoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    normal = normalize(gl_NormalMatrix * gl_Normal);
    vertexColor = gl_Color;
    isLikelyWater = step(vertexColor.b, 0.98) * step(0.3, vertexColor.a) * step(vertexColor.a, 0.9);

    // Small, simple single-sine bob - toon water reads better a bit
    // more restrained/graphic than a busy multi-wave surface.
    vec4 worldPos = gl_Vertex;
    vec3 absoluteWorldPos = worldPos.xyz + cameraPosition;
    float upFacing = smoothstep(0.3, 0.8, normal.y);
    float wave = sin(absoluteWorldPos.x * 0.5 + absoluteWorldPos.z * 0.5 + frameTimeCounter * 0.8);
    worldPos.y += wave * 0.05 * isLikelyWater * upFacing;

    vec4 position = gl_ModelViewMatrix * worldPos;
    viewPos = position.xyz;
    gl_Position = gl_ProjectionMatrix * position;
}
