#include "/lib/all_the_libs.glsl"
#include "/global/gbuffers.vsh"
#include "/global/wind.glsl"

void main() {
    init_generic();

    #if WATER_TEXTURE_MODE == 1 || WATER_TEXTURE_MODE == 2
    // transfer water color through glcolor. should be faster
    if(material == 10001) {
        const vec4 BaseColor = vec4(f_WATER_RED, f_WATER_GREEN, f_WATER_BLUE, f_WATER_ALPHA);
        glcolor.rgb = mix_preserve_c1lum(BaseColor.rgb, glcolor.rgb, f_BIOME_WATER_CONTRIBUTION);
        glcolor.rgb = to_linear(glcolor.rgb);
        glcolor.a = BaseColor.a;
    }
    #else
    glcolor.rgb = to_linear(glcolor.rgb);
    #endif

    #ifdef WAVY_PLANTS
    if (ViewPos.z > -64 && material == 10001) {
        vec3 WorldPos = view_player(ViewPos, false);
        WorldPos += cameraPosition;

        if (fract(WorldPos.y + 0.005) > 0.15) {
            // Helios: use the shared wind function for water surface bobbing.
            // We only use the vertical component (y) of the displacement,
            // and pass IsUpperHalf=true since water surfaces are always
            // "tips" in this context.
            vec3 Displacement = helios_foliage_wind(WorldPos, 10001, true);
            WorldPos.y += Displacement.x; // amplitude scalar in x channel

            WorldPos -= cameraPosition;
            WorldPos = mat3(gbufferModelView) * WorldPos;
            gl_Position = gl_ProjectionMatrix * vec4(WorldPos, 1);
        }
    }
    #endif

    #if TAA_MODE >= 2
    gl_Position.xy += taaJitter * gl_Position.w;
    #endif
}
