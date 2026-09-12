#version 120

#include "/lib/settings.glsl"

varying vec4 vColor;

void main() {
    // Store the unprocessed vanilla line colour in a dedicated overlay target.
    // Depth testing remains owned by Minecraft/Iris during this geometry pass.
    gl_FragData[0] = vColor;
}

/* RENDERTARGETS: 2 */
