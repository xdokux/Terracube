#include "/lib/all_the_libs.glsl"

#include "/global/gbuffers.vsh"
#include "/global/seasons.glsl"
#include "/global/wind.glsl"

flat out vec2 AtlasScale;
flat out vec2 AtlasOffset;
out vec3 TangentPos;
out vec3 TangentLightPos;

// For POM
mat3 get_tbn_matrix() {
        mat3 tbn;
        tbn[0] = mat3(gbufferModelViewInverse) * normalize(gl_NormalMatrix * at_tangent.xyz);
        tbn[2] = mat3(gbufferModelViewInverse) * normalize(gl_NormalMatrix * gl_Normal);
        tbn[1] = cross(tbn[0], tbn[2]) * sign(at_tangent.w);
        return tbn;
}

vec3 get_foliage_player_interaction(vec3 PlayerPos) {
    vec3 Offset;
    vec3 PlayerPosFeet = PlayerPos + vec3(0, 0.5, 0);
    #ifdef IS_IRIS
        PlayerPosFeet += relativeEyePosition; // Fix 3rd person
    #endif
    Offset.xz = PlayerPosFeet.xz * exp(-len2(PlayerPosFeet) * 2.5) * 1.25;
    Offset.y = 0;
    if (material == 10004) {
        if (gl_MultiTexCoord0.t < mc_midTexCoord.t)
            PlayerPos += Offset;
    }
    else if (material == 10005) {
        if (gl_MultiTexCoord0.t < mc_midTexCoord.t)
            PlayerPos += Offset / 2;
    }
    else if (material == 10006) {
        if (gl_MultiTexCoord0.t > mc_midTexCoord.t)
            PlayerPos += Offset / 2;
        else
            PlayerPos += Offset;
    }
    return PlayerPos;
}

void main() {
    init_generic();

    #ifdef SEASONS
        glcolor = get_seasons_color(glcolor);
    #endif

    #ifdef WAVY_PLANTS
    if (ViewPos.z > -64 && material >= 10002 && material <= 10006 && material != 10003) {
        vec3 WorldPos = view_player(ViewPos, false);
        #ifdef FOLIAGE_PLAYER_INTERACTION
            WorldPos = get_foliage_player_interaction(WorldPos);
        #endif
        WorldPos += cameraPosition;

        // Helios: which half of the plant is this vertex in?
        // Top half (texcoord.t < mid) sways; bottom half barely moves.
        bool IsUpperHalf = gl_MultiTexCoord0.t < mc_midTexCoord.t;
        vec3 Displacement = helios_foliage_wind(WorldPos, material, IsUpperHalf);

        // Helios: for non-leaf plants, only apply the displacement to the
        // upper half (preserves mellow's behavior of rigid bases).
        // Leaves get full displacement since they sway as a canopy.
        if (material == 10002) {
            WorldPos += Displacement;
        } else if (IsUpperHalf) {
            WorldPos += Displacement;
        }

        WorldPos -= cameraPosition;
        WorldPos = mat3(gbufferModelView) * WorldPos;
        gl_Position = gl_ProjectionMatrix * vec4(WorldPos, 1);
    }
    #endif

    #if TAA_MODE >= 2
    gl_Position.xy += taaJitter * gl_Position.w;
    #endif

    vec2 midcoord = mc_midTexCoord.xy;
    AtlasScale = abs(texcoord - midcoord) * 2;
    AtlasOffset = min(texcoord, 2 * midcoord - texcoord);
    TangentPos = view_player(ViewPos, false) * get_tbn_matrix();
    TangentLightPos = view_player(sunOrMoonPosN, false) * get_tbn_matrix();
}
