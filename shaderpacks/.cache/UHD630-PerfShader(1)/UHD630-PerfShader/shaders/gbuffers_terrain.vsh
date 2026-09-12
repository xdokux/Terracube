#version 120

uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 vColor;
varying vec3 normal;
varying vec4 shadowPos;

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
    // This is what actually fixes "blobby"/detached-looking shadows on
    // small casters like a player - without it, the shadow map's finite
    // texel size causes self-shadowing artifacts that read as a fuzzy
    // blob instead of a clean silhouette.
    vec3 worldNormal = normalize(mat3(gbufferModelViewInverse) * normal);
    worldPos.xyz += worldNormal * 0.06;

    shadowPos = shadowProjection * shadowModelView * worldPos;
}
