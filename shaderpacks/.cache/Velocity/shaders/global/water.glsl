// Helios: beautiful water.
//
// Replaces mellow's flat water with:
//   - Multi-octave procedural normal mapping (2 octaves of Gerstner-ish waves)
//   - Proper Schlick Fresnel with a slightly higher IOR for water
//   - Tight GGX sun specular highlight (the "sunglint on lake" look)
//   - Depth-dependent color absorption (deep water goes dark blue/green)
//   - Shoreline foam (small foam ring where water meets terrain)
//   - Soft refraction (distort the underwater terrain sample by the wave normal)
//
// All effects are toggleable via #defines from lib/settings.glsl. The
// original mellow functions (sky_reflection, ssr, flipped_image_ref,
// get_reflection) are preserved so existing call sites keep working.

// -----------------------------------------------------------------------------
// Original mellow helpers (kept intact)
// -----------------------------------------------------------------------------

float water_fog(vec3 ScreenPos) {
    float TerrainDepth = texture(depthtex1, ScreenPos.xy).x;
    TerrainDepth = linearize_depth(TerrainDepth);
    float ScreenDepth = linearize_depth(ScreenPos.z);
    return smoothstep(0, 48, TerrainDepth - ScreenDepth) * WATER_FOG_STRENGTH;
}

vec3 get_water_normal(vec2 Coords, vec3 WorldNormal) {
    if (abs(WorldNormal.y) < 0.99) {
        Coords -= frameTimeCounter * normalize(WorldNormal.xz) * 3;
    }
    vec2 N = noise_water(Coords);
    return normalize(vec3(N.x, N.y, 1 - (N.x * N.x + N.y * N.y)));
}

vec3 sky_reflection(vec3 ReflectedVec, float WNy, float Dist, const bool ReflectSun) {
    #ifdef DIMENSION_OVERWORLD
            vec3 SunGlare = get_sun_glare(Dist);
            vec3 Reflection = get_sky(ReflectedVec, SunGlare);
        #ifdef REFLECT_SUN
            if (WNy > 0.01 && ReflectSun) { // Prevent sun from being reflected on sides of blocks
                Reflection.rgb += round_sun(Dist) * 4 * isOutdoorsSmooth;
            }
        #endif
        return Reflection;
    #else
        return to_linear(fogColor.rgb);
    #endif
}

float flipped_image_ref(vec3 RVec, vec3 ViewPos, bool IsDH, out vec3 SamplePos) {
    #ifdef DISTANT_HORIZONS
    float Offset = min(1000, 50 + dhRenderDistance / 4);
    #else
    float Offset = 50 + far / 4;
    #endif

    SamplePos = view_screen(ViewPos + RVec * Offset, IsDH);
    if(SamplePos.xy == vec2(clamp(SamplePos.x, -0.2, 1.2), clamp(SamplePos.y, 0, 1))) {
        bool IsDHReal;
        float RealDepth = get_depth_solid_lq(SamplePos.xy, IsDHReal);
        #ifdef DISTANT_HORIZONS
            if(SamplePos.z >= 1) {
                SamplePos = view_screen(ViewPos + RVec * Offset, true);
            }
        #endif
        if(SamplePos.z < 1 && SamplePos.z > 0.56 && RealDepth < 1) {
            SamplePos.z = RealDepth;
            vec3 ViewPosReal = screen_view(SamplePos, IsDHReal);
            if(len2(ViewPosReal) + 25 > len2(ViewPos)) {
                return 1 - linstep(0.5, 0.7, abs(SamplePos.x - 0.5));
            }
        }
    }
    return 0.0;
}

float ssr(vec3 RVec, vec3 ScreenPos, vec3 ViewPos, float Fresnel, float Dither, bool IsDH, out vec3 ExpectedPos) {
    // Convert RVec to screenspace
    vec3 Offset = normalize(view_screen(ViewPos + RVec, IsDH) - ScreenPos);
    vec3 Len = (step(0, Offset) - ScreenPos) / Offset;
    float MinLen = min(Len.y, Len.z) / SSR_STEPS;
    Offset *= MinLen;

    ExpectedPos = ScreenPos + Offset * Dither;
    for (int i = 1; i <= SSR_STEPS; i++) {
        float RealDepth = get_depth_solid_lq(ExpectedPos.xy, IsDH);
        if (RealDepth < 0.56) {
            break;
        }

        if (ExpectedPos.z > RealDepth) {
            // Depth based rejection
            if (ExpectedPos.z - RealDepth > abs(Offset.z * (0.5 * SSR_STEPS))) {
                break;
            }

            // Binary refinement
            for (int j = 1; j <= int(round(Fresnel * 3)); j++) {
                Offset /= 2;
                vec3 EPos1 = ExpectedPos - Offset;
                float RDepth1 = get_depth_solid_lq(EPos1.xy, IsDH);
                if (EPos1.z > RDepth1) {
                    ExpectedPos = EPos1;
                }
            }
            return 1.0 - linstep(0.5, 0.7, abs(0.5 - ExpectedPos.x));
        }
        ExpectedPos += Offset;
    }
    return 0.0;
}

vec3 get_reflection(vec3 ScreenPos, vec3 ViewPos, vec3 ViewPosN, vec3 WaterNormal, float Dither, float Fresnel, float Smoothness, float WNy, const bool ReflectSun, bool IsDH) {
    vec3 ReflectedVec = reflect(ViewPosN, WaterNormal);

    float Hit = 0;
    vec3 RayPos;
    #if REFLECTIONS == 2
        Hit = ssr(ReflectedVec, ScreenPos, ViewPos, Fresnel, Dither, IsDH, RayPos);
        #ifdef DISTANT_HORIZONS
            if(Hit == 0)
                Hit = flipped_image_ref(ReflectedVec, ViewPos, IsDH, RayPos);
        #endif
    #elif REFLECTIONS == 3
        Hit = flipped_image_ref(ReflectedVec, ViewPos, IsDH, RayPos);
    #endif

    vec3 FinalColor = vec3(0);
    if(Hit > 0) {
        #ifdef ROUGH_REFLECTIONS
            if(Smoothness < 1) {
                float BlurSize = 500 * distance(ViewPos, screen_view(RayPos, IsDH)) * smoothness_to_roughness(Smoothness);
                return blur_variable(RayPos.xy, BlurSize, gaux1);
            } else
        #endif
            FinalColor = texture(gaux1, RayPos.xy).rgb * Hit;
    }
    if(Hit < 1) {
        float Dist = dot(ReflectedVec, sunPosN);
        FinalColor += (1 - Hit) * sky_reflection(ReflectedVec, WNy, Dist, ReflectSun);
    }
    return FinalColor;
}

// -----------------------------------------------------------------------------
// Helios: beautiful water helpers
// -----------------------------------------------------------------------------

// Multi-octave procedural water normal. Uses mellow's noise_water() for the
// low-frequency swell, optionally layered with a higher-frequency detail pass.
// `Octaves` controls sample count: 1 = 2 texture samples, 2 = 4 samples.
// Returns a tangent-space normal (z=up).
vec3 helios_water_normal_lod(vec2 Coords, vec3 WorldNormal, int Octaves) {
    // Base wave (mellow's existing noise_water): 2 texture samples.
    vec2 BaseN = noise_water(Coords);

    vec2 N = BaseN;
    if (Octaves >= 2) {
        // High-frequency detail: one extra noise_water call (2 more samples).
        vec2 DetailN = noise_water(Coords * 3.1 + vec2(17.3, 9.7)) * 0.35;
        N = BaseN + DetailN;
    }

    N *= HELIOS_WATER_NORMAL_STRENGTH;
    return normalize(vec3(N.x, N.y, 1.0 - (N.x * N.x + N.y * N.y)));
}

// Convenience: full-quality (2-octave) normal.
vec3 helios_water_normal(vec2 Coords, vec3 WorldNormal) {
    return helios_water_normal_lod(Coords, WorldNormal, 2);
}

// Schlick Fresnel with the standard water IOR (1.333). F0 = ((n-1)/(n+1))^2.
const float HELIOS_WATER_F0 = 0.0202; // ~ (0.333 / 1.333)^2

float helios_water_fresnel(vec3 ViewDir, vec3 Normal) {
    float CosTheta = clamp(dot(Normal, -ViewDir), 0.0, 1.0);
    // Schlick. We deliberately do NOT push Fresnel all the way to 1.0 at
    // grazing angles - that makes distant water turn fully white from sky
    // reflections. Cap the maximum at 0.85 to keep some water color visible.
    float F = HELIOS_WATER_F0 + (1.0 - HELIOS_WATER_F0) * pow(1.0 - CosTheta, 5.0);
    return min(F, 0.85);
}

// GGX specular for the sun glint on water. Capped to avoid over-bright spikes.
float helios_water_sun_spec(vec3 ViewDir, vec3 Normal, vec3 LightDir) {
    vec3 H = normalize(LightDir - ViewDir);
    float NdotH = max(dot(Normal, H), 0.0);
    float NdotV = max(dot(Normal, -ViewDir), 0.0);
    float NdotL = max(dot(Normal, LightDir), 0.0);
    if (NdotL <= 0.0 || NdotV <= 0.0) return 0.0;

    float a = HELIOS_WATER_SUN_SPEC_ROUGHNESS;
    float a2 = a * a;
    float NdotH2 = NdotH * NdotH;
    float D = a2 / (PI * pow2(NdotH2 * (a2 - 1.0) + 1.0));
    // Simplified geometry term for sharp specular highlights.
    float G = 0.25 / max(NdotV * NdotL, 1e-3);
    // Helios: cap at 4.0 (down from 12.0) to prevent the white-out spikes.
    // The cap is multiplied by SUN_DIRECT later, which is already HDR-bright.
    return min(D * G, 4.0);
}

// Depth-dependent water absorption. Darkens + tints the water color based
// on how far the ray travels through water before hitting terrain.
// `WaterThicknessOut` and `VerticalWaterThicknessOut` are filled with depth info
// so callers can reuse them for the foam pass without re-sampling depthtex1.
vec3 helios_water_depth_color(vec3 ScreenPos, vec3 BaseColor, float SkyBrightness, out float WaterThicknessOut, out float VerticalWaterThicknessOut, bool IsDH) {
    WaterThicknessOut = 0.0;
    VerticalWaterThicknessOut = 0.0;
    #if defined(HELIOS_WATER_DEEP_COLOR) || defined(HELIOS_WATER_FOAM)
    // Read the opaque terrain depth behind the water.
    float TerrainDepth = texture(depthtex1, ScreenPos.xy).x;
    float LinearTerrain = linearize_depth(TerrainDepth);
    float LinearWater = linearize_depth(ScreenPos.z);
    WaterThicknessOut = max(0.0, LinearTerrain - LinearWater);

    // Reconstruct world/player space Y coordinates to measure true vertical water depth.
    vec3 ViewPosDiff = screen_view(vec3(ScreenPos.xy, TerrainDepth), IsDH) - screen_view(ScreenPos, IsDH);
    VerticalWaterThicknessOut = max(0.0, -view_player(ViewPosDiff, IsDH).y);
    #endif

    #ifdef HELIOS_WATER_DEEP_COLOR
    // Beer-Lambert absorption. Two coefficients: a fast one for the warm
    // wavelengths (absorbed quickly, so deep water looks blue) and a slow
    // one for blue (transmitted, so shallow water stays transparent).
    // Numbers are tuned per-block (~1 meter), so depth in blocks = WaterThickness.
    float Absorb = HELIOS_WATER_ABSORPTION;
    vec3 AbsorptionCoeff = vec3(0.45, 0.18, 0.06) * Absorb; // R absorbed fast, B slow
    vec3 Transmittance = exp(-AbsorptionCoeff * WaterThicknessOut);

    // Mix the base water color toward the deep-water tint as depth grows.
    // Deep water is a dark blue-green that blends with the sky on the horizon.
    // Helios: damp the DeepTint brightness so deep water doesn't glow white
    // when SkyBrightness is high (e.g. noon). Cap at 0.5 * SkyBrightness.
    vec3 DeepTint = to_linear(vec3(0.02, 0.08, 0.12)) * min(SkyBrightness, 0.5);
    return BaseColor.rgb * Transmittance + DeepTint * (1.0 - Transmittance);
    #else
    return BaseColor.rgb;
    #endif
}

// Shoreline foam: add a thin foam ring where the water is very shallow
// (just above the terrain). Uses VerticalWaterThickness to prevent foam on vertical walls/pits.
float helios_water_foam(float WaterThickness, float VerticalWaterThickness, vec3 ScreenPos, float Dither) {
    #ifdef HELIOS_WATER_FOAM
    // Foam band: 0-0.8 blocks of vertical water depth.
    float EffectiveThickness = max(VerticalWaterThickness, WaterThickness * 0.25);
    float ShoreFoam = 1.0 - smoothstep(0.0, 0.8, EffectiveThickness);

    // Add dithered noise so the foam edge isn't a clean line.
    ShoreFoam *= 0.5 + 0.5 * texture(noisetex, ScreenPos.xy * 60.0 + Dither * 4.0).r;

    return clamp(ShoreFoam * HELIOS_WATER_FOAM_DENSITY, 0.0, 0.6);
    #else
    return 0.0;
    #endif
}

// Soft refraction shimmer: offset the brightness subtly using the wave normal.
// Helios: this is intentionally very subtle - the original version brightened
// the water by up to 15% on every wave, contributing to the white-out.
vec3 helios_water_refraction(vec3 ScreenPos, vec3 WaterNormal, vec3 BaseColor) {
    #ifdef HELIOS_WATER_REFRACTION
    float Shimmer = (WaterNormal.x + WaterNormal.y) * 0.06;
    return BaseColor * (1.0 + Shimmer);
    #else
    return BaseColor;
    #endif
}

// -----------------------------------------------------------------------------
// Helios: beautiful water main entry point
// Drop-in replacement for get_fancy_water(). Same signature, same return
// semantics, but with all the Helios improvements baked in.
// -----------------------------------------------------------------------------

vec4 get_fancy_water(vec3 ScreenPos, vec3 ViewPos, vec3 ViewPosN, vec3 PlayerPos, vec4 BaseColor, float SkyBrightness, mat3 TBN, float Dither, bool IsDH) {
    #ifndef HELIOS_BEAUTIFUL_WATER
        // Fallback: original mellow behavior.
        // ----- Mellow fallback water path -----
        #if REFLECTIONS != 0
            vec3 WorldNormal = view_player(TBN[2], IsDH);
            #ifdef WATER_NORMALS
                vec3 NormalMap = get_water_normal(PlayerPos.xz + cameraPosition.xz, WorldNormal);
                vec3 WaterNormal = TBN * NormalMap;
            #else
                vec3 WaterNormal = TBN[2];
            #endif

            float Fresnel = schlick(-ViewPosN, WaterNormal, 0.02) * SkyBrightness;

            if (WorldNormal.y > -0.01) {
                vec3 Reflection = get_reflection(ScreenPos, ViewPos, ViewPosN, WaterNormal, Dither, Fresnel, 1, WorldNormal.y, true, IsDH);
                BaseColor.rgb += Reflection * Fresnel;
            }
        #endif

        #ifndef DISTANT_HORIZONS
            if (isEyeInWater == 0) {
                BaseColor.a = min(BaseColor.a + water_fog(ScreenPos), 1);
            }
        #endif

        return BaseColor;
    #else
        // ----- Helios beautiful water path -----
        bool IsPuddle = BaseColor.a < 0.01 && dot(BaseColor.rgb, BaseColor.rgb) < 1e-4;

        float ViewDist = length(ViewPos);
        float lodDist = float(HELIOS_WATER_LOD_DISTANCE);
        float lodFade = 1.0 - smoothstep(lodDist * 0.7, lodDist * 1.3, ViewDist);
        int NormalOctaves = ViewDist > lodDist ? 1 : 2;

        vec3 WorldNormal = view_player(TBN[2], IsDH);
        vec3 NormalMap = helios_water_normal_lod(PlayerPos.xz + cameraPosition.xz, WorldNormal, NormalOctaves);
        if (WorldNormal.y < 0.99) {
            NormalMap.xy *= 0.4;
        }
        vec3 WaterNormal = TBN * NormalMap;

        float WaterThickness = 0.0;
        float VerticalWaterThickness = 0.0;
        if (!IsPuddle) {
            BaseColor.rgb = helios_water_depth_color(ScreenPos, BaseColor.rgb, SkyBrightness, WaterThickness, VerticalWaterThickness, IsDH);

            if (lodFade > 0.01) {
                vec3 refrColor = helios_water_refraction(ScreenPos, WaterNormal, BaseColor.rgb);
                BaseColor.rgb = mix(BaseColor.rgb, refrColor, lodFade);
            }
        }

        float Fresnel = helios_water_fresnel(ViewPosN, WaterNormal) * SkyBrightness;

        if (WorldNormal.y > -0.01) {
            #if REFLECTIONS != 0
                vec3 Reflection = get_reflection(ScreenPos, ViewPos, ViewPosN, WaterNormal, Dither, Fresnel, 1, WorldNormal.y, true, IsDH);
                BaseColor.rgb = mix(BaseColor.rgb, Reflection, clamp(Fresnel, 0.0, 0.55));
            #else
                #ifdef DIMENSION_OVERWORLD
                vec3 SkyRefl = mix(SKY_GROUND, SKY_TOP, clamp(WaterNormal.y * 0.5 + 0.5, 0.0, 1.0));
                SkyRefl *= 0.4 * SkyBrightness;
                BaseColor.rgb = mix(BaseColor.rgb, SkyRefl, clamp(Fresnel, 0.0, 0.45));
                #endif
            #endif
        }

        // ----- Sun specular highlight -----
        #if defined(HELIOS_WATER_SPECULAR) && defined(DIMENSION_OVERWORLD)
        if (WorldNormal.y > -0.01 && isEyeInWater == 0) {
            float Spec = helios_water_sun_spec(ViewPosN, WaterNormal, sunOrMoonPosN);
            float TimeFade = dayStrength + sunsetStrength * 0.6 + sunriseStrength * 0.6;
            float WeatherFade = 1.0 - (rainStrength + thunderStrength * 0.5) * 0.8;
            float SpecDistFade = 1.0 - smoothstep(300.0, 600.0, ViewDist);
            vec3 SoftSun = min(SUN_DIRECT, vec3(1.4));
            BaseColor.rgb += SoftSun * (Spec * HELIOS_WATER_SUN_SPEC_INTENSITY * TimeFade * WeatherFade * SpecDistFade * 0.35);
        }
        #endif

        // ----- Shoreline foam (skip for puddles + far pixels) -----
        #if defined(HELIOS_WATER_FOAM) && !defined(GBUFFERS_TERRAIN)
        if (!IsPuddle && lodFade > 0.01) {
            float Foam = helios_water_foam(WaterThickness, VerticalWaterThickness, ScreenPos, Dither);
            // Helios: foam color is a SOFT off-white, and the mix factor is
            // capped at 0.35 (down from 0.8). This keeps the shoreline
            // readable as foam without turning shallow water into a white sheet.
            vec3 FoamColor = to_linear(vec3(0.75, 0.80, 0.82)) * (0.6 + 0.4 * SkyBrightness);
            BaseColor.rgb = mix(BaseColor.rgb, FoamColor, Foam * 0.35);
        }
        #endif

        // Water fog (keep mellow's existing behavior for non-DH).
        #ifndef DISTANT_HORIZONS
            if (isEyeInWater == 0) {
                BaseColor.a = min(BaseColor.a + water_fog(ScreenPos), 1);
            }
        #endif

        return BaseColor;
    #endif
}
