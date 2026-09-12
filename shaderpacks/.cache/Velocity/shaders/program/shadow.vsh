#include "/lib/all_the_libs.glsl"
#include "/global/wind.glsl"

attribute vec4 mc_Entity;
attribute vec2 mc_midTexCoord;

out vec2 texcoord;

void main() {
        texcoord = get_texcoord(gl_TextureMatrix[0], gl_MultiTexCoord0);
        vec4 glcolor = gl_Color;
    float material = mc_Entity.x;

        vec3 ViewPos = (gl_ModelViewMatrix * gl_Vertex).xyz;

        #ifdef WAVY_PLANTS
    if (ViewPos.z > -64 && material >= 10002 && material <= 10006 && material != 10003) {
        vec3 WorldPos = view_player(ViewPos, false);
        WorldPos += cameraPosition;

        // Helios: use the shared wind function so shadows match the
        // visible foliage motion. This is critical - if the shadow uses
        // a different wind formula than gbuffers_terrain, foliage will
        // cast mismatched "ghost" shadows.
        bool IsUpperHalf = gl_MultiTexCoord0.t < mc_midTexCoord.t;
        vec3 Displacement = helios_foliage_wind(WorldPos, material, IsUpperHalf);

        if (material == 10002) {
            WorldPos += Displacement;
        } else if (IsUpperHalf) {
            WorldPos += Displacement;
        }

        WorldPos -= cameraPosition;
        WorldPos = mat3(gbufferModelView) * WorldPos;
        gl_Position = gl_ProjectionMatrix * vec4(WorldPos, 1);
    } else if (ViewPos.z > -64 && material == 10001) {
        // Water surface in the shadow pass - bob vertically using the
        // shared wind amplitude so the shadow edges wobble with the water.
        vec3 WorldPos = view_player(ViewPos, false);
        WorldPos += cameraPosition;
        if (fract(WorldPos.y + 0.005) > 0.15) {
            vec3 Displacement = helios_foliage_wind(WorldPos, 10001, true);
            WorldPos.y += Displacement.x;
        }
        WorldPos -= cameraPosition;
        WorldPos = mat3(gbufferModelView) * WorldPos;
        gl_Position = gl_ProjectionMatrix * vec4(WorldPos, 1);
    } else
    #endif
        gl_Position = ftransform();

    gl_Position.xyz = distort(gl_Position.xyz);
}
