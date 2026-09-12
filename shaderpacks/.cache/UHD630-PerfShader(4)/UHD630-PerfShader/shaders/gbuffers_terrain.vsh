#version 120

#define SHADOW_MAP_BIAS 0.9 // Shadow distortion strength - MUST match shadow.vsh [0.0 0.5 0.7 0.8 0.85 0.9 0.95]

uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 vColor;
varying vec3 normal;
varying vec4 shadowPos;

float getDistortFactor(vec2 pos) {
    return (1.0 - SHADOW_MAP_BIAS) + length(pos) * SHADOW_MAP_BIAS;
}

vec3 distortShadowClipPos(vec3 clipPos) {
    float distortFactor = getDistortFactor(clipPos.xy);
    return vec3(clipPos.xy / distortFactor, clipPos.z);
}

void main() {
    gl_Position = gl_ProjectionMatrix * gl_ModelViewMatrix * gl_Vertex;

    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    vColor   = gl_Color;
    normal   = gl_NormalMatrix * gl_Normal; // view-space normal

    // Move vertex from view space -> camera-relative world space ->
    // shadow clip space. This matches the space shadowModelView expects.
    vec4 viewPos  = gl_ModelViewMatrix * gl_Vertex;
    vec4 worldPos = gbufferModelViewInverse * viewPos;

    // Normal-offset bias: nudge the shadow-casting position slightly
    // along the surface normal before projecting into shadow space.
    // Reduced to 0.02 blocks (was 0.06) since that was likely visibly
    // shifting shadow silhouettes for small/detailed casters.
    vec3 worldNormal = normalize(mat3(gbufferModelViewInverse) * normal);
    worldPos.xyz += worldNormal * 0.02;

    vec4 shadowClip = shadowProjection * shadowModelView * worldPos;
    shadowClip.xyz = distortShadowClipPos(shadowClip.xyz);
    shadowPos = shadowClip;
}
