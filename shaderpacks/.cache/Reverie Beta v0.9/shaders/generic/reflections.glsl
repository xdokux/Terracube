// "Sampling Visible GGX Normals with Spherical Caps" 
// https://arxiv.org/abs/2306.05044

// Sampling the visible hemisphere as half vectors (our method)
vec3 SampleVndf_Hemisphere(vec2 u, vec3 wi) {
    // sample a spherical cap in (-wi.z, 1]
    float phi = 2.0f * PI * u.x;
    float z = fma((1.0f - u.y), (1.0f + wi.z), -wi.z);
    float sinTheta = sqrt(clamp(1.0f - z * z, 0.0f, 1.0f));
    float x = sinTheta * cos(phi);
    float y = sinTheta * sin(phi);
    vec3 c = vec3(x, y, z);
    // compute halfway direction;
    vec3 h = c + wi;
    // return without normalization (as this is done later)
    return h;
}

vec3 SampleVndf_GGX(vec2 u, vec3 wi, vec2 alpha) {
    // warp to the hemisphere configuration
    vec3 wiStd = normalize(vec3(wi.xy * alpha, wi.z));
    // sample the hemisphere (see implementation 2 or 3)
    vec3 wmStd = SampleVndf_Hemisphere(u, wiStd);
    // warp back to the ellipsoid configuration
    vec3 wm = normalize(vec3(wmStd.xy * alpha, wmStd.z));
    // return final normal
    return wm;
}

bool raytrace(vec3 ScreenPos, vec3 ViewPos, vec3 Dir, bool IsDH, float Dither, out vec3 RayPos) {
    int Steps = SSR_STEPS;
    vec3 Offset = normalize(view_screen(ViewPos + Dir, IsDH, true) - ScreenPos);
    vec3 Len = (step(0, Offset) - ScreenPos) / Offset;
    float MinLen = min(Len.x, min(Len.y, Len.z)) / Steps;
    Offset *= MinLen;

    RayPos = ScreenPos + Offset * Dither;
    for (int i = 1; i <= Steps; i++) {
        float RealDepth = get_depth_solid(RayPos.xy, IsDH);
        if (RealDepth < 0.56) {
            break;
        }
        if (RayPos.z > RealDepth && RayPos.z - RealDepth < abs(Offset.z) * 4) {
            // Binary refinement
            for (int i = 1; i <= Steps / 12; i++) {
                Offset /= 2;
                vec3 EPos1 = RayPos - Offset;
                float RDepth1 = get_depth_solid(EPos1.xy, IsDH);
                if (EPos1.z > RDepth1) {
                    RayPos = EPos1;
                }
            }
            return true;
        }
        RayPos += Offset;
    }
    return false;
}

bool flipped_image_ref(vec3 RVec, vec3 ViewPos, bool IsDH, out vec3 SamplePos) {
    #ifdef DISTANT_HORIZONS
    float Offset = min(1000, 50 + dhRenderDistance / 4);
    #else
    float Offset = 50 + far / 4;
    #endif

    SamplePos = view_screen(ViewPos + RVec * Offset, IsDH, true);
    if(SamplePos.xy == vec2(clamp(SamplePos.x, -0.1, 1.1), clamp(SamplePos.y, 0, 1))) {
        bool IsDHReal;
        float RealDepth = get_depth_solid(SamplePos.xy, IsDHReal);
        #ifdef DISTANT_HORIZONS
            if(SamplePos.z >= 1) {
                SamplePos = view_screen(ViewPos + RVec * Offset, true, true);
            }
        #endif
        if(SamplePos.z < 1 && SamplePos.z > 0.56 && RealDepth < 1) {
            SamplePos.z = RealDepth;
            vec3 ViewPosReal = screen_view(SamplePos, IsDHReal, true);
            if(len2(ViewPosReal) + 25 > len2(ViewPos)) {
                return true;
            }
        }
    }
    return false;
}

bool sample_ref_capture(vec3 StartPos, vec3 Dir, bool IsDH, float Dither, out vec3 Color, out vec3 ExpectedPos) {
    StartPos = view_player(screen_view(StartPos, IsDH, true), IsDH);
    Dir = view_player(Dir, false);
    vec3 Step = Dir * 32;
    ExpectedPos = StartPos + Dir * Dither;
    for(int i = 0; i < 8; i++) {
        float EPosLen = length(ExpectedPos);
        vec2 uv = to_spherical(ExpectedPos / EPosLen);
        vec4 RefData = texture(colortex11, uv);
        if(RefData.a < 0.0001 || RefData.a >= farLod) {
            break;
        }
        if(EPosLen > RefData.a && EPosLen - RefData.a < 128) {
            Color = RefData.rgb;
            return true;
        }
        ExpectedPos += Step;
    }
    return false;
}

vec3 ssr(vec3 Normal, Positions Pos, bool IsDH, float LightmapSky, float Dither) {
    vec3 Dir = reflect(Pos.ViewN, Normal);

    vec3 RayPos; 
    bool Hit = raytrace(Pos.Screen, Pos.View, Dir, IsDH, Dither, RayPos);
    #ifdef DISTANT_HORIZONS
        if(!Hit) {
            Hit = flipped_image_ref(Dir, Pos.View, IsDH, RayPos);
        }
    #endif

    // if(Hit) return vec3(100, 0,0 );
    vec3 SphereColor;
    bool SphereHit = false;
    #ifdef REFLECTION_CAPTURE
        if(!Hit)
            SphereHit = sample_ref_capture(Pos.Screen, Dir, IsDH, Dither, SphereColor, RayPos);
    #endif

    if(Hit || SphereHit) {
        vec3 TerrainColor;
        if(Hit)
            TerrainColor = texture(colortex0, RayPos.xy).rgb;
        else
            TerrainColor = SphereColor;
        vec3 StartPos = Pos.Player;
        vec3 EndPos = view_player(screen_view(RayPos, IsDH, true), IsDH);
        mat2x3 Vl = aerial_prespective_ld(StartPos, EndPos, Pos.Screen, view_player(Dir, IsDH), Dither, 0, false, IsDH);
        TerrainColor = blend_vl(TerrainColor, Vl); 

        #ifdef BORDER_FOG
            vec3 SkyColor = get_sky(Dir, false, EndPos.y);
            SkyColor = blend_vl(SkyColor, mat2x3(Vl[0], Vl[1] * 0.85));
            TerrainColor = get_border_fog(length(EndPos), TerrainColor, SkyColor);
        #endif

        float Dist = length(EndPos);
        #ifdef DISTANT_HORIZONS
            Dist /= dhRenderDistance;
        #else
            Dist /= far;
        #endif
        return TerrainColor;
    } else {
        #ifdef 
        // Sky reflections
        vec3 StartPos = Pos.Player;
        vec3 EndPos = view_player(Dir, IsDH);
        vec3 SkyColor = get_sky(Dir, false, EndPos.y);
        #if (defined CLOUDS) && (defined DIMENSION_OVERWORLD) 
            vec3 P = EndPos;
            vec2 CloudPos = vec2(P.x, P.z) / (1 + P.y);
            SkyColor += texture(colortex3, (CloudPos * 0.5 + 0.5) * resolutionInv * CLOUD_TEX_SIZE).rgb;
        #endif

        SkyColor += get_stars(EndPos);
        mat2x3 Vl = aerial_prespective_ld(StartPos, view_player(Dir * 1000, IsDH), Pos.Screen, view_player(Dir, IsDH), Dither, 0, false, IsDH);
        SkyColor = blend_vl(SkyColor, Vl);
        return SkyColor * LightmapSky;
    }
}
