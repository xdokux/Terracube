#version 120

// Shadow map distortion: warps shadow-space coordinates so texels are
// packed much more densely near the center (where the player usually
// is) and more sparsely toward the edges of the shadow distance. This
// gives noticeably sharper close-up shadows for the SAME shadow map
// resolution/cost - the single best value-for-performance shadow
// quality improvement available. Must be applied identically here AND
// in every gbuffers_*.vsh / composite1.fsh that samples the shadow map,
// or shadow lookups will be misaligned.
#define SHADOW_MAP_BIAS 0.9 // Shadow distortion strength - higher = sharper near player, softer far away [0.0 0.5 0.7 0.8 0.85 0.9 0.95]

uniform mat4 shadowModelView;
uniform mat4 shadowProjection;

varying vec2 texcoord;
varying vec4 vColor;

float getDistortFactor(vec2 pos) {
    return (1.0 - SHADOW_MAP_BIAS) + length(pos) * SHADOW_MAP_BIAS;
}

vec3 distortShadowClipPos(vec3 clipPos) {
    float distortFactor = getDistortFactor(clipPos.xy);
    return vec3(clipPos.xy / distortFactor, clipPos.z);
}

void main() {
    vec4 clipPos = shadowProjection * shadowModelView * gl_Vertex;
    clipPos.xyz = distortShadowClipPos(clipPos.xyz);
    gl_Position = clipPos;

    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vColor = gl_Color;
}
