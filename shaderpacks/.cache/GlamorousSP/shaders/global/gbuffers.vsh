out vec2 LightmapCoords;
out vec2 texcoord;
out vec4 glcolor;
attribute vec4 mc_Entity;
attribute vec2 mc_midTexCoord;
flat out uint material;
out vec3 ViewPos;
out mat3 TBN;

#include "/global/light_colors.vsh"
#include "/global/sky.glsl"
#include "/global/pbr.glsl"
#include "/global/shadows.glsl"
#include "/global/lighting.glsl"

attribute vec4 at_tangent;

void init_generic() {
    init_colors();

    gl_Position = ftransform();
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    LightmapCoords = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    #ifdef GBUFFERS_BLOCK
        material = blockEntityId != 65535 ? uint(blockEntityId) : 0;
    #else
        material = uint(mc_Entity.x + 0.5);
    #endif    
    ViewPos = (gl_ModelViewMatrix * gl_Vertex).xyz;
    glcolor = gl_Color;

    vec3 Normal = normalize(gl_NormalMatrix * gl_Normal);
    if (material == 10002 || material == 10004 || material == 10005 || material == 10006) {
        Normal = gbufferModelView[1].xyz;
        // Make grass darker at the bottom. It looks better this way
        if (gl_MultiTexCoord0.t > mc_midTexCoord.t && (material == 10004 || material == 10005)) Normal *= 0.5;
    }

    #ifdef DH_TERRAIN
        TBN[0] = normalize(gbufferModelView[0].xyz);
        TBN[1] = normalize(gbufferModelView[2].xyz);
        TBN[2] = Normal;
    #else
        vec3 tangent = normalize(gl_NormalMatrix * normalize(at_tangent.xyz));
        vec3 binormal = cross(tangent, Normal) * sign(at_tangent.w);
        TBN = mat3(tangent, binormal, Normal);
    #endif

    LightmapCoords = tweak_lightmap_vertex(LightmapCoords, SUN_AMBIENT, normalize(ViewPos), view_player(ViewPos, false));
}
