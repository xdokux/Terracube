varying vec2 texcoord;
varying vec4 color;
#include "/lib/all_the_libs.glsl"
#include "/lib/distort.glsl"

attribute vec3 at_midBlock;
uniform mat4 shadowModelViewInverse;

in vec2 mc_Entity;
flat varying float blockID;

void main() {
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    color = gl_Color;
    blockID = mc_Entity.x;

    vec3 modelPos = gl_Vertex.xyz + at_midBlock.xyz / 64.0;
    vec3 viewPos = (gl_ModelViewMatrix * vec4(modelPos, 1.0)).xyz;
    vec3 scenePos = (shadowModelViewInverse * vec4(viewPos, 1.0)).xyz;

    // Calculate the 3D grid position
    vec3 voxelPos = scenePos + fract(cameraPosition) + vec3(32.0);
    ivec3 gridPos = ivec3(floor(voxelPos));
#if defined(VOXELIZE) && !defined(FAST_SHADOWS)
    // Inside your boundary check...
    if (gridPos.x >= 0 && gridPos.x < 64 && gridPos.y >= 0 && gridPos.y < 64 && gridPos.z >= 0 && gridPos.z < 64) {
        int packedData = 0; // Default to Air (0 << 4 | 0)

        if (blockID == 100.0) {
            packedData = (2 << 4) | SOUL_LIGHT; // Soul Torch: ID 2, Level 15
        } else if (blockID == 101.0) {
            packedData = (3 << 4) | FIRE_LIGHT; // Normal Torch: ID 3, Level 15
        } else if(blockID == 102.0) {
            packedData = (4 << 4) | REDSTONE_LIGHT; // Redstone: ID 4, Level 15
        } else if(blockID == 103.0) {
            packedData = (5 << 4) | PORTAL_LIGHT; // Portal: ID 5, Level 15
        } else if(blockID == 104.0) {
            packedData = (6 << 4) | END_ROD_LIGHT; // End Rod: ID 6, Level 15
        } else if(blockID == 2.0 || (blockID >=10001 && blockID <=10006)) {
            packedData = (0 << 4) | 0; // Glass: ID 0, Level 0
        } else {
            packedData = (1 << 4) | 0;  // Solid Block: ID 1, Level 0
        }

        // Write the packed data to Buffer A!
        atomicMax(voxels[getIndex(gridPos) + OFFSET_A], packedData);
    }
#endif
    gl_Position = ftransform();
    gl_Position.xyz = distortShadowClipPos(gl_Position.xyz);
}