// Helios fork - composite1: dedicated sun-rays (crepuscular rays) pass.
//
// This pass runs after deferred1 (sky, fog, ssao) and before the bloom passes.
// It traces a short radial screen-space march from each pixel toward the sun's
// screen position and accumulates a soft, additive light streak. The streak is
// gated by sun visibility, time of day and weather, so it cleanly disappears
// at night, underground, or during heavy rain.
//
// Algorithm: GPU Gems 3 "Volumetric Light Scattering" (Kenny Mitchell), adapted
// to mellow's HDR pipeline. We sample scene color along the ray, weight each
// sample by a luminance high-pass (so only the bright sky around the sun
// contributes), apply a per-sample decay, and add the result additively.
//
// Performance: O(SUNRAYS_QUALITY) texture samples per pixel. At the FAST default
// of 24 samples this is comparable to a single-tap bloom pass on most GPUs.

#include "/lib/all_the_libs.glsl"

in vec2 texcoord;

/* DRAWBUFFERS:0 */
layout(location = 0) out vec4 Color;

// Compute a sun/moon direct-light color in this pass, since light_colors.vsh
// varyings are not available in composite passes. Mirrors the math in
// light_colors.vsh but only keeps the SUN_DIRECT term.
vec3 helios_sun_direct_color() {
    float LHeight = sin(sunAngleAtHome * PI * 2);

    vec3 SunColor = vec3(0.0);
    if (LHeight > 0.0) {
        const vec3 SUNRISE_SUN = to_linear(vec3(f_SUNRISE_RED, f_SUNRISE_GREEN, f_SUNRISE_BLUE));
        const vec3 NOON_SUN    = to_linear(vec3(f_NOON_RED,    f_NOON_GREEN,    f_NOON_BLUE));
        const vec3 SUNSET_SUN  = to_linear(vec3(f_SUNSET_RED,  f_SUNSET_GREEN,  f_SUNSET_BLUE));
        SunColor = SUNRISE_SUN * sunriseStrength + NOON_SUN * dayStrength + SUNSET_SUN * sunsetStrength;
    } else {
        SunColor = to_linear(vec3(f_MOON_RED, f_MOON_GREEN, f_MOON_BLUE));
        const float MPI_DIV2 = MOON_PHASE_INFLUENCE / 2.0;
        float MoonPhaseFactor = cos(float(worldDay % 8) / 8.0 * TAU) * MPI_DIV2 + (1.0 - MPI_DIV2);
        SunColor *= MoonPhaseFactor;
    }

    SunColor *= smoothstep(0.0, 0.2, abs(LHeight));

    float DesatFactor  = 1.0 - rainStrength * 0.5;
    float DarkenFactor = 1.0 - rainStrength * 0.5;
    #ifdef IS_IRIS
        DesatFactor  *= 1.0 - thunderStrength * 0.33;
        DarkenFactor *= 1.0 - thunderStrength * 0.5;
    #endif
    SunColor = apply_saturation(SunColor, DesatFactor) * DarkenFactor;
    return SunColor;
}

void main() {
    Color = texture(colortex0, texcoord);

    #if defined(SUNRAYS) && defined(DIMENSION_OVERWORLD)
        // === Perf: skip the entire pass when the player is underground ===
        // isOutdoorsSmooth is 1 when the player has sky exposure, 0 in caves.
        // Tracing sun rays inside a cave is wasted work - there's no sky to
        // scatter through. This is the single biggest perf win for cave-heavy
        // playthroughs.
        if (isOutdoorsSmooth > 0.01) {
        // Sun (or moon) direction in view space. sunOrMoonPosN already swaps
        // to the moon direction at night, so we get subtle moon-rays too.
        vec3 LightDirView = sunOrMoonPosN;

        // Only trace when the light source is in front of the camera.
        // View space: -Z is forward, so a forward-facing light has z < 0.
        if (LightDirView.z < 0.0) {
            // Project the light direction to screen space.
            vec4 LightClip = gbufferProjection * vec4(LightDirView, 1.0);
            vec2 LightScreen = (LightClip.xy / LightClip.w) * 0.5 + 0.5;

            // Skip when the light is far off-screen (no rays to cast).
            // A small margin around the screen lets rays fade in/out smoothly
            // as the sun enters or leaves the view.
            if (all(greaterThan(LightScreen, vec2(-0.5))) && all(lessThan(LightScreen, vec2(1.5)))) {
                // Sun direct color (warm at day, cool at night).
                vec3 SunColor = helios_sun_direct_color();

                // Time-of-day strength. Day gets full strength, night gets a
                // subtle moon-ray factor.
                float TimeStrength = dayStrength + sunsetStrength * 0.7 + sunriseStrength * 0.7 + nightStrength * 0.35;

                // Weather attenuation.
                float Weather = 1.0 - (rainStrength + thunderStrength * 0.5) * 0.75;

                if (TimeStrength > 0.01 && Weather > 0.01) {
                    // Ultra-fast 8-sample depth-only crepuscular ray engine
                    const int SAMPLES = 8;
                    vec2 RayVector = (LightScreen - texcoord);
                    float RayLen = length(RayVector);
                    vec2 Step = RayVector / float(SAMPLES);

                    float Dither = dither(gl_FragCoord.xy);
                    vec2 Pos = texcoord + Step * Dither;

                    float Decay = 1.0;
                    float TotalWeight = 0.0;
                    float SkyVisibility = 0.0;
                    float OccludedCount = 0.0;

                    for (int i = 0; i < SAMPLES; i++) {
                        float DepthSample = texture(depthtex0, Pos).r;
                        float isSky = float(DepthSample >= 1.0);
                        
                        SkyVisibility += isSky * Decay;
                        OccludedCount += (1.0 - isSky);
                        TotalWeight += Decay;

                        Decay *= 0.88;
                        Pos += Step;
                    }
                    SkyVisibility /= max(TotalWeight, 1e-3);

                    // Rays ONLY form when there is a contrast between occluded blocks and open sky
                    float ContrastMask = smoothstep(0.0, 3.0, OccludedCount) * smoothstep(0.05, 0.3, SkyVisibility);

                    float Falloff = clamp(1.0 - RayLen * 1.3, 0.0, 1.0);
                    Falloff = pow(Falloff, 2.0);

                    vec3 RayTint = isEyeInWater == 1
                        ? to_linear(vec3(f_WATER_RED, f_WATER_GREEN, f_WATER_BLUE)) * 1.5 + 0.3
                        : vec3(1.0);

                    vec3 SoftSunColor = min(SunColor, vec3(1.2));
                    vec3 Rays = SoftSunColor * (ContrastMask * SUNRAYS_INTENSITY * Falloff * 0.12 * TimeStrength * Weather * SUNRAYS_EXPOSURE) * RayTint;

                    Color.rgb += Rays;
                }
            }
        }
        } // end isOutdoorsSmooth guard
    #endif
}
