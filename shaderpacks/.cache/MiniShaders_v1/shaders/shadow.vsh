#version 120

// GamesofDev is non chalant
varying vec2 texcoord;
varying vec4 glColor;
varying float blockId;

attribute float mc_Entity;

#define SHADOW_DISTORT_FACTOR 0.10

vec3 distort(vec3 shadowPos) {
    float distortFactor = length(shadowPos.xy) + SHADOW_DISTORT_FACTOR;
    shadowPos.xy /= distortFactor;
    shadowPos.z *= 0.5;
    return shadowPos;
}

void main() {
    gl_Position = ftransform();
    
    
    gl_Position.xyz = distort(gl_Position.xyz);
    
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).st;
    glColor = gl_Color;
    blockId = mc_Entity;
}
