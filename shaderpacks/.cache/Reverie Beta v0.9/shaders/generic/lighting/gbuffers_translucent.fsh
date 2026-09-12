#ifndef VOXY_TERRAIN
    in Data {
        vec2 lmcoord;
        vec2 texcoord;
        vec4 glcolor;
        flat float Id;
        flat mat3 TBN;
        vec3 ViewPos;
        float chunkFade;
    } DataIn;
#else
    struct Data {
        vec2 lmcoord;
        vec2 texcoord;
        vec4 glcolor;
        float Id;
        mat3 TBN;
        vec3 ViewPos;
        float chunkFade;
    } DataIn;
    void map_voxy_param_to_varying(VoxyFragmentParameters param) {
        DataIn.texcoord = param.uv;
        DataIn.lmcoord = param.lightMap;
        DataIn.lmcoord = max(DataIn.lmcoord * 1.06667 - 0.0648, 0);
        DataIn.Id = (param.customId - 10000.0);
        DataIn.glcolor = param.tinting;
        DataIn.ViewPos = screen_view(vec3(DataIn.texcoord, gl_FragCoord.z), true, false);
        // from Cortex
        vec3 normal = vec3(
                        uint((param.face >> 1) == 2),
                        uint((param.face >> 1) == 0),
                        uint((param.face >> 1) == 1)
                    ) *
            (float(int(param.face) & 1) * 2.0 - 1.0);
        DataIn.TBN = tbn_normal(player_view(normal, true));
        DataIn.chunkFade = 1;
    }
#endif

/* RENDERTARGETS:0,1,2,5 */

layout(location = 0) out vec4 Albedo;
layout(location = 1) out vec4 buf1;
layout(location = 2) out vec4 buf2;
layout(location = 3) out vec4 Shadow;

#ifdef VOXY_TERRAIN
    void init_frag_translucent(VoxyFragmentParameters param) {
#else
    void init_frag_translucent() {
#endif
    vec3 ScreenPos = gl_FragCoord.xyz * vec3(resolutionInv, 1);
    #if (defined DH_TERRAIN) || (defined VOXY_TERRAIN)
        bool IsDH = true;
    #else
        bool IsDH = false;
    #endif
    Positions Pos = get_positions(ScreenPos.xy, ScreenPos.z, IsDH, false);

    #if (defined DISTANT_HORIZONS) && (!defined VOXY)
        float Dither = bayer8(gl_FragCoord.xy);
        if (transition_to_dh(Pos.Player, Dither)) {
            discard;
            return;
        }
        #ifdef DH_TERRAIN
            float Depth = texture(depthtex0, ScreenPos.xy).x;
            if(Depth < 1) {
                discard; return;
            }
        #endif

        #if (defined DH_NOISE) && (defined DH_TERRAIN)
            Albedo.rgb = dh_noise(Pos.Player, Albedo.rgb);
        #endif
    #endif
    
    #ifndef GBUFFERS_BASIC
        #ifdef VOXY_TERRAIN
            Albedo = vec4(DataIn.glcolor.rgb, 1) * param.sampledColour;
        #else
            #ifdef GBUFFERS_WATER
                Albedo = vec4(DataIn.glcolor.rgb, 1) * texture(gtexture, DataIn.texcoord);
            #else
                Albedo = DataIn.glcolor * texture(gtexture, DataIn.texcoord);
            #endif
        #endif
    #else
        Albedo = glcolor_flat;
    #endif

    if(Albedo.a < 0.01) {
        discard;
    }

    Albedo.rgb = srgb_linear(Albedo.rgb);

    #ifdef GBUFFERS_ENTITIES
    Albedo.rgb = mix(Albedo.rgb, entityColor.rgb, entityColor.a);
    #endif

    if (DataIn.Id == MATERIAL_WATER) {
        Albedo = vec4(0);
    }

    MaterialProperties Mat;
    Mat.Albedo = Albedo.rgb;

    if(DataIn.Id != MATERIAL_WATER) {
        vec3 PackNormal = get_normal(DataIn.texcoord, vec2(0), vec2(0));
        Mat.Normal = DataIn.TBN * PackNormal;
    } else {
        Mat.Normal = DataIn.TBN[2];
    }

    Mat.FlatNormal = DataIn.TBN[2];

    #ifdef IRIS_FEATURE_FADE_VARIABLE
        Mat.chunkFade = DataIn.chunkFade;
        Albedo.a *= Mat.chunkFade;
    #else
        Mat.chunkFade = 1;
    #endif

    Mat.Lightmap = DataIn.lmcoord;
    if(Mat.Lightmap.y > 1 / 255.0)
        Mat.Lightmap += bayer8(gl_FragCoord.xy) / 255.0;

    Mat.SSS = get_sss(DataIn.texcoord);
    Mat.Emissiveness = get_emissiveness(DataIn.texcoord);

    Mat.Smoothness = texture(specular, DataIn.texcoord).r;
    Mat.F0 = texture(specular, DataIn.texcoord).g;
    Mat.Id = DataIn.Id;

    buf1 = pack_material_buf1(Mat, IsDH);
    buf2 = pack_material_buf2(Mat, IsDH);

    #ifndef GBUFFERS_DAMAGEDBLOCK
        if (DataIn.Id != MATERIAL_WATER) {
            Albedo.rgb = calc_lighting(Pos, Mat, IsDH, DataIn.texcoord, false, Shadow);
        }
        else {
            Shadow.r = get_shadow_unfiltered(Pos.Player, Mat.FlatNormal, Mat.Lightmap.y);
        }
    #endif
}
