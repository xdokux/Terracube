#ifndef VOXY_TERRAIN
    flat in uint material;
    in vec2 LightmapCoords;
    in vec2 texcoord;
    in vec4 glcolor;
    in vec3 ViewPos;
    in mat3 TBN;

    flat in vec3 SUN_DIRECT;
    flat in vec3 SUN_AMBIENT;
    flat in vec3 SKY_TOP;
    flat in vec3 SKY_GROUND;
#else
    uint material;
    vec2 LightmapCoords;
    vec2 texcoord;
    vec4 glcolor;
    vec3 ViewPos;
    mat3 TBN;
    #include "/global/light_colors.vsh"

    void map_voxy_param_to_varying(VoxyFragmentParameters param) {
        texcoord = param.uv;
        LightmapCoords = param.lightMap;
        material = uint(param.customId);
        glcolor = param.tinting;
        ViewPos = screen_view(vec3(texcoord, gl_FragCoord.z), true);
        // from Cortex
        vec3 normal = vec3(
                        uint((param.face >> 1) == 2),
                        uint((param.face >> 1) == 0),
                        uint((param.face >> 1) == 1)
                    ) *
            (float(int(param.face) & 1) * 2.0 - 1.0);
        if(material == 10002 || material == 10004 || material == 10005 || material == 10006) {
            normal = vxModelView[1].xyz;
        }
        TBN = tbnNormal(player_view(normal, true));
    }
#endif
#include "/global/sky.glsl"
#include "/global/pbr.glsl"
#include "/global/shadows.glsl"
#include "/global/lighting.glsl"