// Never include this file directly. Use gbuffers.fsh/vsh instead

// Helios: modern Complementary-reimagine-style lighting helpers.
// These wrap the existing mellow lighting with optional modern features
// (wrapped diffuse, ambient SSS, directional sky ambient, simple multi-
// bounce sky light) so the look is softer and more filmic without
// breaking the original pipeline.

// Wrapped diffuse: shift the half-Lambert cosine so surfaces just barely
// facing away from the sun still get a bit of direct light, simulating
// light bleeding through thin geometry. More pleasant than the harsh
// max(0, NdotL) cutoff.
float helios_wrapped_diffuse(float NdotL) {
    #ifdef HELIOS_WRAPPED_DIFFUSE
        // Half-Lambert (Half-Life style): remap [-1, 1] -> [0, 1] then square.
        // Softens the terminator and lifts the shadow side a touch.
        float Half = NdotL * 0.5 + 0.5;
        return Half * Half;
    #else
        return max(0.0, NdotL);
    #endif
}

// Ambient SSS: fake subsurface scattering on foliage / vegetation by
// adding a warm back-light when the player is roughly looking into the
// sun through thin material. Very cheap, very effective on leaves.
vec3 helios_ambient_sss(vec3 SunDirect, vec3 Normal, vec3 ViewPosN, vec3 LightDirN, float NdotL) {
    #ifdef HELIOS_AMBIENT_SSS
        // Back-side light: bright when -LightDirN faces the camera and the
        // front side is in shadow (NdotL < 0). This mimics light passing
        // through leaves / grass.
        float BackNdotL = max(0.0, dot(-Normal, LightDirN));
        float BackVdotL = max(0.0, dot(-ViewPosN, LightDirN));
        // Combine + apply a soft cutoff so SSS only kicks in near the
        // terminator (not in full sunlight, not in full shadow).
        float Factor = BackNdotL * BackVdotL;
        Factor *= smoothstep(-0.4, 0.1, NdotL);
        Factor *= 1.0 - smoothstep(0.1, 0.6, NdotL);
        // Warm tint, mimicking chlorophyll translucency.
        vec3 Tint = vec3(1.0, 0.55, 0.3);
        return SunDirect * Factor * Tint * 0.5;
    #else
        return vec3(0.0);
    #endif
}

// Directional sky ambient: replace the flat "up-facing gets SKY_TOP, down-
// facing gets SKY_GROUND" with a softer hemisphere + a small bias toward
// the sun's azimuth so ambient wraps around objects in a believable way.
vec3 helios_directional_ambient(vec3 SkyTop, vec3 SkyGround, vec3 Normal, vec3 LightDirN) {
    #ifdef HELIOS_DIRECTIONAL_AMBIENT
        float UpDot = Normal.y * 0.5 + 0.5;
        vec3 Hemispheric = mix(SkyGround, SkyTop, UpDot);
        // Sun-facing bias: adds a touch of sun-tinted ambient on faces
        // toward the sun, even when NdotL < 0 (shadow side). This is the
        // key to the "Complementary" look - shadows still get warm sky bounce.
        float SunBias = max(0.0, dot(Normal, LightDirN)) * 0.35 + 0.05;
        vec3 SunTint = mix(vec3(1.0), SkyTop * 1.4, 0.5);
        return Hemispheric + SunTint * SunBias * 0.15;
    #else
        float UpDot = Normal.y * 0.5 + 0.5;
        return mix(SkyGround, SkyTop, UpDot);
    #endif
}

// Simple sky bounce: brighten the ambient slightly when looking at the
// sky so outdoor scenes read as more "airy". Subtle effect, on by default.
vec3 helios_sky_bounce(vec3 Ambient, vec3 SkyTop) {
    #ifdef HELIOS_SKY_BOUNCE
        return Ambient + SkyTop * 0.03;
    #else
        return Ambient;
    #endif
}

vec2 tweak_lightmap_vertex(vec2 LightmapCoords, inout vec3 SunAmbient, inout vec3 SunDirect, vec3 ViewPosN, vec3 Normal, vec3 PlayerPos) {
    LightmapCoords = max(LightmapCoords * 1.06667 - 0.0625, 0);

    LightmapCoords.x = pow(LightmapCoords.x, 4.0001 - LM_FALLOFF_CURVE);

    #ifdef DIMENSION_OVERWORLD
        // Combine ambient lighting with the sky and some other tricks to make it less flat
        float NdotU = clamp(dot(gbufferModelView[1].xyz, Normal), -1, 1);
        vec3 SkyGround = SKY_GROUND + get_sun_glare(clamp(dot(Normal, sunPosN), -1, 1));
        SunAmbient = mix(SunAmbient, mix(SkyGround, SKY_TOP, NdotU * 0.5 + 0.5), 0.4);

        #ifdef IS_IRIS
            if(lightningBoltPosition.w > 0) {
                float VdotLi = 1 - min(1, distance(lightningBoltPosition.xyz, PlayerPos) * 0.01);
                vec3 LiBPN = normalize((player_view(lightningBoltPosition.xyz, false) - ViewPos));
                float NdotLi = max(0, dot(Normal, LiBPN)) * 0.8 + 0.2;
                SunAmbient += vec3(1) * NdotLi * VdotLi;
            }
        #endif
    #endif

    #ifdef HANDHELD_LIGHTS
        #ifdef IS_IRIS
            vec3 ViewPosOffset = player_view(PlayerPos + relativeEyePosition, false);
        #else
            vec3 ViewPosOffset = ViewPos;
        #endif
        float Dist = length(ViewPosOffset);

        float HandheldLight = max((heldBlockLightValue - Dist) / 15.0, 0);
        #ifndef GBUFFERS_BASIC
            HandheldLight *= max(0, dot(-normalize(ViewPosOffset), Normal));
        #endif
        HandheldLight = pow(HandheldLight, 4.0 - HANDHELD_FALLOFF_CURVE);
        LightmapCoords.x = max(LightmapCoords.x, HandheldLight);
    #endif

    #ifdef LM_FLICKER
        LightmapCoords.x *= (1 - LM_FLICKER_STRENGTH) + texture(noisetex, vec2(frameTimeCounter / 8, 0)).r * LM_FLICKER_STRENGTH;
    #endif

    #ifndef DIMENSION_OVERWORLD
        LightmapCoords.y = 1;
    #endif

    #if (defined DYNAMIC_SHADOWS) && (defined DIMENSION_OVERWORLD)
        // Helios: slightly stronger direct sun + slightly weaker ambient,
        // tuned to balance the modern wrapped diffuse (which lifts shadow
        // sides a touch on its own).
        SunDirect *= 1.3;
        SunAmbient *= 0.82;
    #endif

    return LightmapCoords;
}

vec3 tweak_lightmap(vec3 Albedo, vec3 PlayerPos, vec2 LightmapCoords, vec2 texcoord, vec3 ScreenPos, mat3 TBN, float Dither, float PomShadow) {
    vec3 LightColorFinal = SUN_AMBIENT;
    #ifdef VOXY_TERRAIN
        LightmapCoords = tweak_lightmap_vertex(LightmapCoords, LightColorFinal, SUN_DIRECT, normalize(ViewPos), TBN[2], PlayerPos);
    #endif
    #ifdef PBR_NORMAL
        vec3 PackNormal; float PackAo;
        decode_normal(texcoord, PackNormal, PackAo);
        PackNormal = TBN * PackNormal;
        LightColorFinal *= PackAo;
    #else
        vec3 PackNormal = TBN[2];
    #endif
    #ifdef PBR_SPECULAR
        float Smoothness, F0, PackSSS, Porosity, Emissiveness;
        decode_specular(texcoord, Smoothness, F0, PackSSS, Porosity, Emissiveness);
    #endif
    #if (defined DH_TERRAIN) || (defined VOXY_TERRAIN)
        bool IsDH = true;
    #else
        bool IsDH = false;
    #endif
    vec3 ViewPosN = normalize(ViewPos);
    #if (defined DIMENSION_OVERWORLD) || (defined DIMENSION_END)
        #ifdef DIMENSION_END
            float NdotL = max(0, dot(TBN[2], gbufferModelView[1].xyz));
        #else
            float NdotL = dot(PackNormal, sunOrMoonPosN);
        #endif

        NdotL *= PomShadow;


        #ifndef DIMENSION_END
            float Shadow = 0;
            float NdotLflat = dot(TBN[2], sunOrMoonPosN);
            #ifdef DYNAMIC_SHADOWS
                float SSSStrength = float(material > 10001) * PBR_SSS_STRENGTH; // Subsurface scattering
                #ifdef PBR_SPECULAR
                    SSSStrength = max(SSSStrength, PackSSS);
                #endif
                bool DoSSS = SSSStrength > 0;
                // Perf: skip the expensive dynamic shadow lookup entirely
                // when the pixel has no sky exposure (deep caves). No sky =
                // no sun = no shadow to compute. The static fallback below
                // returns 0 for skylight < 0.82 anyway, so this is purely
                // a perf optimization that avoids the shadowmap texture
                // samples + PCF loop.
                if(LightmapCoords.y > 0.01 && (NdotLflat > -1e-6 || (DoSSS && material >= 10002))) {
                    float ShadowS = 1, ShadowD = 1;
                    float Fade = shadow_fade(PlayerPos, shadowDistance);

                    if(Fade < 1) {
                        ShadowD = get_shadow_dynamic(ViewPos, PlayerPos, false, TBN[2], NdotL, LightmapCoords.y, DoSSS, Dither);

                        if(DoSSS) {
                            LightColorFinal += SUN_DIRECT * ShadowD * exp(-(1 - SSSStrength) * 5 * abs(NdotL)) * max(ISOTROPIC_PHASE, xlf_phase(dot(ViewPosN, sunOrMoonPosN), 0.6)) * 4 * (1-Fade);
                        }
                    }
                    if(Fade > 0) {
                        ShadowS = get_shadow_static(LightmapCoords.y);
                    }

                    Shadow = mix(ShadowD, ShadowS, Fade);
                }
            #else
                if(NdotLflat > -1e-6)
                    Shadow = get_shadow_static(LightmapCoords.y);
            #endif

            // Helios: modern direct lighting.
            #ifdef HELIOS_MODERN_LIGHTING
                // Wrapped diffuse: shift the cosine so surfaces just barely
                // facing away from the sun still get a bit of direct light.
                float WrappedNdotL = helios_wrapped_diffuse(NdotL);
                // Wrapped diffuse should not double-brighten fully-lit faces,
                // so blend it toward the raw clamped NdotL at high NdotL.
                float DirectNdotL = mix(WrappedNdotL, max(0.0, NdotL), smoothstep(0.6, 1.0, max(0.0, NdotL)));
                // Apply shadow factor to the direct light.
                DirectNdotL *= Shadow;
                // Add wrapped light as a softer "sky bounce" effect on the
                // shadow side - subtle, just enough to lift deep blacks.
                // This is intentionally NOT shadowed, so shadowed sides
                // still get a tiny ambient lift.
                float WrapBounce = WrappedNdotL * (1.0 - Shadow) * 0.18;
                LightColorFinal += SUN_DIRECT * DirectNdotL;
                LightColorFinal += SUN_DIRECT * WrapBounce;

                // Ambient SSS for foliage.
                // Perf: skip when there's no sky exposure (underground / deep cave).
                // SSS simulates light bleeding through leaves, which requires sunlight.
                #ifdef HELIOS_AMBIENT_SSS
                if(material >= 10003 && material <= 10006 && LightmapCoords.y > 0.1) {
                    LightColorFinal += helios_ambient_sss(SUN_DIRECT, TBN[2], ViewPosN, sunOrMoonPosN, NdotLflat);
                }
                #endif
                // Keep NdotL as the shadowed value for downstream code
                // (the PBR specular block below checks NdotL > 0).
                NdotL = max(0.0, NdotL) * Shadow;
            #else
                NdotL = max(0, NdotL) * Shadow;
                LightColorFinal += SUN_DIRECT * NdotL;
            #endif
        #endif

        // Helios: PBR-free sun glint on flat terrain.
        // Disabled if PBR_SPECULAR is on (the real PBR specular takes over).
        // Perf: skip when skylight is low (caves/night) - no sun to glint with.
        #if defined(HELIOS_SUN_GLINT) && defined(DIMENSION_OVERWORLD) && !defined(PBR_SPECULAR) && !defined(DH_TERRAIN) && !defined(VOXY_TERRAIN)
        {
            // Only apply to upward-facing smooth surfaces (stone, sand, etc.)
            // Rough heuristic: flat top + decent sky light + not foliage.
            float UpDot = clamp(TBN[2].y, 0.0, 1.0);
            if(UpDot > 0.5 && material < 10003 && NdotL > 0.0 && LightmapCoords.y > 0.3) {
                vec3 H = normalize(sunOrMoonPosN - ViewPosN);
                float NdotH = max(0.0, dot(PackNormal, H));
                // Tight GGX-like specular lobe.
                float Roughness = 0.18;
                float a = Roughness * Roughness;
                float Spec = pow(NdotH, 2.0 / (a * a) - 2.0);
                Spec *= HELIOS_SUN_GLINT_STRENGTH * Shadow * (1.0 - rainStrength * 0.7);
                // Modulate by albedo luminance so dark blocks don't glint.
                float AlbedoLum = get_luminance(Albedo);
                LightColorFinal += SUN_DIRECT * Spec * (0.3 + 0.7 * AlbedoLum);
            }
        }
        #endif
    #endif

    // === Velocity: distinct torch / lantern light ===
    // Mellow uses a single flat orange for ALL block light. Velocity gives
    // torchlight its own identity with a warm flickering flame color and a
    // temperature shift (white-hot near the source, warm orange at distance).
    vec3 TorchColor;
    float TorchPow = LightmapCoords.x;
    #ifdef PBR_SPECULAR
        TorchPow += Emissiveness;
    #endif

    #ifdef HELIOS_TORCH_LIGHT
    {
        // Base torch color from the existing LM_RED/GREEN/BLUE sliders.
        vec3 BaseTorch = to_linear(vec3(f_LM_RED, f_LM_GREEN, f_LM_BLUE));

        // Warmth shift: push the color warmer (more red/orange, less blue)
        // or cooler (for soul-fire / blue-flame builds).
        vec3 WarmthTint = vec3(1.0 + HELIOS_TORCH_WARMTH * 0.6,
                                1.0 + HELIOS_TORCH_WARMTH * 0.2,
                                1.0 - HELIOS_TORCH_WARMTH * 0.8);
        BaseTorch *= WarmthTint;

        // Temperature shift: near the light source (high TorchPow) the flame
        // is white-hot; at distance (low TorchPow) it cools to warm orange.
        // This simulates blackbody radiation cooling.
        float TempMix = mix(1.0, 0.0, smoothstep(0.0, 0.8, TorchPow));
        // White-hot tint at the source, fades out as you move away.
        vec3 HotTint = vec3(1.0, 0.95, 0.85); // slightly warm white
        vec3 CoolTint = vec3(1.0, 0.6, 0.25);  // warm orange
        vec3 TempColor = mix(HotTint, CoolTint, TempMix * HELIOS_TORCH_TEMPERATURE);

        TorchColor = BaseTorch * mix(vec3(1.0), TempColor, HELIOS_TORCH_TEMPERATURE);

        // Per-source flicker: each torch gets its own phase based on world
        // position, so they don't all pulse in sync. Two noise samples at
        // different frequencies for an irregular flame-like flicker.
        #ifdef HELIOS_TORCH_FLICKER
        if (TorchPow > 0.01) {
            vec3 WorldPos = PlayerPos + cameraPosition;
            // Hash the world position to get a per-torch phase.
            float Phase = fract(floor(WorldPos.x) * 0.1031 +
                                floor(WorldPos.y) * 0.1030 +
                                floor(WorldPos.z) * 0.0973) * TAU;
            // Two sines at slightly different frequencies -> irregular flicker.
            float Flicker = sin(frameTimeCounter * 8.0 + Phase) * 0.6
                          + sin(frameTimeCounter * 13.7 + Phase * 1.7) * 0.4;
            Flicker = Flicker * 0.5 + 0.5; // remap to 0..1
            // Modulate torch brightness (not color) by the flicker.
            float FlickerMod = 1.0 + (Flicker - 0.5) * HELIOS_TORCH_FLICKER_STRENGTH * 2.0;
            TorchPow *= FlickerMod;
        }
        #endif

        // Overall brightness multiplier.
        TorchPow *= HELIOS_TORCH_BRIGHTNESS;
    }
    #else
        TorchColor = to_linear(vec3(f_LM_RED, f_LM_GREEN, f_LM_BLUE));
    #endif

    // Helios: modern ambient lighting. Replace flat ambient with directional
    // sky ambient + subtle sky bounce. Only applied in the overworld.
    vec3 FinalSkyAmbient = LightColorFinal;
    #if defined(HELIOS_MODERN_LIGHTING) && defined(DIMENSION_OVERWORLD)
    {
        vec3 WorldNormal = view_player(TBN[2], IsDH);
        vec3 DirAmbient = helios_directional_ambient(SKY_TOP, SKY_GROUND, WorldNormal, sunOrMoonPosN);
        DirAmbient = helios_sky_bounce(DirAmbient, SKY_TOP);
        // Blend the original ambient with the directional one - we don't
        // want to fully replace mellow's tuned values, just lift them
        // toward a more filmic hemisphere look.
        FinalSkyAmbient = mix(LightColorFinal, DirAmbient * SUN_AMBIENT * 1.6 + get_min_light(), 0.35);
    }
    #endif

    FinalSkyAmbient = TorchColor * TorchPow + mix(get_min_light(), FinalSkyAmbient, LightmapCoords.y);
    FinalSkyAmbient *= 1 - darknessLightFactor;
    #ifdef PBR_SPECULAR
        FinalSkyAmbient *= 1 - Porosity * wetness * 0.66 * LightmapCoords.y;
    #endif

    FinalSkyAmbient *= Albedo;
    LightColorFinal = FinalSkyAmbient;
    #ifdef PBR_SPECULAR
        if(material != 10001 && !(material >= 10003 && material <= 10006)) {
            bool HandleAsMetal = false;
            #ifdef PBR_SPECULAR_RP_REFLECTIONS
                HandleAsMetal = F0 >= 230.0 / 255.0;
            #endif
            if(HandleAsMetal) {
                LightColorFinal *= 0.25;
            }
            #ifdef DIMENSION_OVERWORLD
                if(NdotL > 0) {
                    vec3 H = normalize(sunOrMoonPosN - ViewPosN);
                    float F = schlick(H, -ViewPosN, F0);
                    LightColorFinal += SUN_DIRECT * NdotL * cook_torrance(-ViewPosN, sunOrMoonPosN, PackNormal, 1 - Smoothness, H, F);
                }
            #endif
            #ifdef PBR_SPECULAR_RP_REFLECTIONS
                if(Smoothness > PBR_SPECULAR_RP_REFLECTIONS_THRESHOLD) {
                    float F = schlick(PackNormal, -ViewPosN, F0);
                    LightColorFinal += Smoothness * F * get_reflection(ScreenPos, ViewPos, ViewPosN, PackNormal, Dither, F, Smoothness, 1, false, IsDH);
                }
            #endif
            if(HandleAsMetal) {
                LightColorFinal *= Albedo;
            }
        }
    #endif

    return LightColorFinal;
}
