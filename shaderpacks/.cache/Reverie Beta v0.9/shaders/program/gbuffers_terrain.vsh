#include "/lib/all_the_libs.glsl"

#define GBUFFERS_TERRAIN

#include "/generic/lighting/gbuffers.vsh"
#include "/generic/weather.glsl"

void main() {
    init_generic();

    if(DataOut.Id >= MATERIAL_TALL_PLANT_LOWER && DataOut.Id <= MATERIAL_LEAVES) {
        vec3 WorldPos = view_player(DataOut.ViewPos, false);
        WorldPos += cameraPosition;

        #ifdef WAVY_PLANTS
            WorldPos = get_wavy_plants(WorldPos, DataOut.Id, gl_MultiTexCoord0.t < mc_midTexCoord.t);
        #endif

        WorldPos -= cameraPosition;
        WorldPos = mat3(gbufferModelView) * WorldPos;
        gl_Position = gl_ProjectionMatrix * vec4(WorldPos, 1);

        // This needs to be redone since the original gl_Position is overwritten
        gl_Position.xy += taaJitter * gl_Position.w;
    }
}
