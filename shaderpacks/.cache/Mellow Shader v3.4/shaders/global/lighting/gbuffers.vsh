out vec2 LightmapCoords;
out vec2 texcoord;
out vec4 glcolor;
attribute vec4 mc_Entity;
attribute vec2 mc_midTexCoord;
flat out float material;
out vec3 ViewPos;
out vec3 Normal;
out vec4 Tangent;
flat out vec2 AtlasScale;
flat out vec2 AtlasOffset;

#include "/global/lighting/light_colors.vsh"
#include "/global/atmosphere/sky.glsl"
#include "/global/pbr.glsl"
#include "/global/lighting/shadows.glsl"
#include "/global/water.glsl"
#include "/global/lighting/lighting.glsl"

attribute vec4 at_tangent;

void init_generic() {
    init_colors();

    gl_Position = ftransform();
    texcoord = get_texcoord(gl_TextureMatrix[0], gl_MultiTexCoord0);
    LightmapCoords = get_lightmap(gl_TextureMatrix[1], gl_MultiTexCoord1);
    #ifdef GBUFFERS_BLOCK
        material = blockEntityId != 65535 ? blockEntityId : 0;
    #else
        material = mc_Entity.x;
    #endif    
    ViewPos = (gl_ModelViewMatrix * gl_Vertex).xyz;
    glcolor = gl_Color;

    Normal = normalize(gl_NormalMatrix * gl_Normal);
    if (material >= 10003 && material <= 10006) {
        Normal = gbufferModelView[1].xyz;
        // Make grass darker at the bottom. It looks better this way
        if (gl_MultiTexCoord0.t > mc_midTexCoord.t && (material == 10004 || material == 10005)) Normal *= 0.5;
    }

    Tangent.xyz = gl_NormalMatrix * normalize(at_tangent.xyz + vec3(1e-9,0,0)); // Prevents nans when at_tangent is 0 (which can happen with some mods)
    Tangent.w = at_tangent.w;

    LightmapCoords = tweak_lightmap_vertex(LightmapCoords, SUN_AMBIENT, SUN_DIRECT, normalize(ViewPos), Normal, view_player(ViewPos, false));

    vec2 midcoord = mc_midTexCoord.xy;
    AtlasScale = abs(texcoord - midcoord) * 2;
    AtlasOffset = min(texcoord, 2 * midcoord - texcoord);
}
