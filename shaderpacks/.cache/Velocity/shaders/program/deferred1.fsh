#define DEFERRED

#include "/lib/all_the_libs.glsl"

#include "/global/gbuffers.fsh"
#include "/global/fog.glsl"
#include "/global/post/ssao.glsl"
#include "/global/outline.glsl"
#include "/global/wind_streaks.glsl"

// Sky, Clouds, etc

/* DRAWBUFFERS:0 */
layout(location = 0) out vec4 Color;

void main() {
    Color = texture(colortex0, texcoord);
    bool IsDH;
    float Depth = get_depth(texcoord, IsDH);
    vec3 ScreenPos = vec3(texcoord, Depth);
    vec3 ViewPos = screen_view(ScreenPos, IsDH);

    vec3 PlayerPos = mat3(gbufferModelViewInverse) * ViewPos;

    vec3 ViewPosN = normalize(ViewPos);
    vec3 PlayerPosN = normalize(PlayerPos);

    float VdotL = dot(ViewPosN, sunPosN);
    vec3 SunGlare = get_sun_glare(VdotL);

    vec3 SkyColor = get_sky_main(ViewPosN, PlayerPosN, SunGlare);
    SkyColor += (ign(gl_FragCoord.xy, false) - 0.5) / 255;

    float Dither = dither(gl_FragCoord.xy);

    if (Depth >= 1) {
        #ifndef CUSTOM_SKYBOXES
            #ifndef DIMENSION_OVERWORLD
            Color = vec4(0, 0, 0, 1);
            #elif defined ROUND_SUN
            SkyColor += round_sun(VdotL);
            #endif

            #ifdef DEBUG_OVERRIDE_SKY
            Color.rgb = SkyColor;
            #else
            Color.rgb += SkyColor;
            #endif

            // Velocity: cartoon wind streaks float in the sky like clouds.
            // Rendered on sky pixels only, so they're occluded by terrain.
            #ifdef HELIOS_WIND_STREAKS
            Color.rgb += velocity_wind_streaks(ViewPosN, PlayerPosN, SkyColor);
            #endif

            if (PlayerPos.y > 0) {
                #if defined DIMENSION_OVERWORLD || defined DIMENSION_END
                Color.rgb += get_stars(PlayerPos);
                #endif

                #ifdef DIMENSION_OVERWORLD
                    Color.rgb = get_clouds(ViewPosN, PlayerPos, PlayerPosN, SunGlare, Color.rgb, Dither);

                    #ifdef AURORA_BOREALIS
                        Color.rgb += get_aurora(PlayerPosN, Dither);
                    #endif
                #endif
            }
        #endif
    }
    
    else if (Depth >= 0.56) { // Skip hand & sky
        #ifdef SSAO
            Color.rgb = ssao(Color.rgb, ViewPos, Dither, IsDH);
        #elif (defined DISTANT_HORIZONS) && (defined SSAO_ON_LODS)
            if(IsDH)
                Color.rgb = ssao(Color.rgb, ViewPos, Dither, IsDH);
        #endif
        #ifdef OUTLINE
            Color.rgb = get_outline(Color.rgb, ScreenPos);
        #endif
    }

    if (Depth >= 0.56) { // Skip JUST the hand
        Color.rgb = get_fog_main(ScreenPos, PlayerPos, Color.rgb, Depth, SkyColor, VdotL, Dither, IsDH);
        #if RAINBOWS > 0
            Color.rgb += get_rainbow(PlayerPos, PlayerPosN);
        #endif

        // === Velocity: rain fog + splash ===
        // Rain fog: extra atmospheric haze + darkening during storms. Makes
        // rain feel "wet" and reduces visibility realistically.
        // Rain splash: bright speckle highlights on wet ground (cheap,
        // screen-space, dithered so it shimmers like real splashes).
        #if defined(HELIOS_RAIN_ENHANCE) && defined(DIMENSION_OVERWORLD)
        if (rainStrength > 0.01 && isOutdoorsSmooth > 0.1) {
            #ifdef HELIOS_RAIN_FOG
            {
                float Dist = length(PlayerPos);
                // Fog builds with distance + rain strength.
                float fogFactor = smoothstep(20.0, 120.0, Dist) * rainStrength * HELIOS_RAIN_FOG_STRENGTH;
                // Darken + desaturate toward a cool grey.
                vec3 rainFogColor = to_linear(vec3(0.35, 0.38, 0.42)) * (0.5 + 0.5 * SkyColor);
                Color.rgb = mix(Color.rgb, rainFogColor, fogFactor * 0.6);
            }
            #endif

            #ifdef HELIOS_RAIN_SPLASH
            // Splash highlights: only on upward-facing surfaces near the player.
            // We use the depth + a dithered noise to fake raindrop impacts.
            if (Depth < 1.0 && length(PlayerPos) < 40.0) {
                // Sample the gbuffer normals texture. The encoding depends on
                // whether PBR_NORMAL is on, but the green channel is reliably
                // high for up-facing surfaces in both encodings. This is a
                // heuristic - good enough for a splash gate.
                vec3 packedNormal = texture(normals, texcoord).xyz;
                // Reconstruct approximate up-facing factor. For labPBR-encoded
                // normals (xy * 2 - 1), a high green channel = up. For the
                // fallback encoding, green is also high for up-facing.
                float upDot = packedNormal.g * 2.0 - 1.0;
                upDot = clamp(upDot, 0.0, 1.0);
                if (upDot > 0.5) {
                    // Dithered noise for splash speckle.
                    float splashNoise = texture(noisetex, gl_FragCoord.xy * 0.3 + frameTimeCounter * 0.5).r;
                    splashNoise = pow(splashNoise, 8.0); // sharpen to speckles
                    float splash = splashNoise * rainStrength * HELIOS_RAIN_SPLASH_INTENSITY;
                    // Brighter speckles, slightly cool tint.
                    Color.rgb += vec3(0.7, 0.75, 0.85) * splash * upDot;
                }
            }
            #endif
        }
        #endif
    }

    #ifdef VOXY
        if(texture(depthtex1, texcoord).r >= 1) {
            vec4 VxData = texture(colortex16, texcoord);
            Color.rgb = mix(Color.rgb, VxData.rgb, VxData.a);
        }
    #endif 
}
