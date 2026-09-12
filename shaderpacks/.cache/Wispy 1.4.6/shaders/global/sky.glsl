mediump float fogify(mediump float x, mediump float w) {
    return w / (x * x + w);
}

// Sun and Moon color blending
mediump vec3 round_sun(mediump float Dist) {
    Dist = Dist * 0.5 + 0.5;
    const mediump vec3 SUN_COLOR  = vec3(5.0, 3.5, 0.8);
    const mediump vec3 MOON_COLOR = vec3(1.0, 1.5, 2.5);
    mediump float What = sunriseStrength + sunsetStrength;
    mediump vec3 Color = SUN_COLOR * (1.0 - smoothstep(0.0, 0.0015, 1.0 - Dist)) * (dayStrength + What);
    Color += MOON_COLOR * smoothstep(0.9995, 1.0, 1.0 - Dist) * (nightStrength + What);
    Color *= 1.0 - rainStrength;
    return Color;
}

// Sun glare calculation
mediump vec3 get_sun_glare(mediump float Dist) {
    const mediump vec3 SUN_GLARE = to_linear(vec3(f_SUN_GLARE_R, f_SUN_GLARE_G, f_SUN_GLARE_B));
    mediump float DarkenFactor = 1.0 - rainStrength * RAIN_SKY_DARKENING;
    #ifdef IS_IRIS
    DarkenFactor *= 1.0 - thunderStrength * 0.75;
    #endif

    mediump vec3 SunGlare = SUN_GLARE * DarkenFactor;
    mediump float Visibility = (sunriseStrength + sunsetStrength);
    Visibility *= Visibility;

    return SunGlare * (Dist * 0.5 + 0.5) * Visibility;
}

// Cloud generation
mediump vec3 get_clouds(mediump vec3 ViewPosN, mediump vec3 PlayerPos, mediump vec3 PlayerPosN,
                        mediump vec3 SunGlare, mediump vec3 SkyColor) {

    mediump vec2 CloudPos = PlayerPos.xz / (PlayerPos.y + length(PlayerPos.xz) / 6.0);
    const mediump float ACTUAL_CLOUD_SPEED = CLOUD_SPEED / 100.0;
    mediump float Animation = float(frameTimeCounter) * ACTUAL_CLOUD_SPEED;
    CloudPos += cameraPosition.xz / 512.0;
    CloudPos = (CloudPos + Animation) * 32.0;

    mediump float Noise = fbm_clouds(CloudPos, CLOUD_QUALITY);
    mediump float CloudAmount = CLOUD_AMOUNT / 100.0 + (rainStrength + thunderStrength) / 10.0;
    Noise *= smoothstep(0.0, 0.4 - CLOUD_OPACITY, Noise - 0.55 + CloudAmount);
    Noise *= smoothstep(0.0, 0.2, PlayerPosN.y);

    const mediump float DENSITY = 1.5;
    mediump float Transmittance = exp(-Noise * DENSITY);
    mediump float Absorbtion = fbm_clouds(CloudPos + to_player_pos(sunOrMoonPosN).xz * 8.0, 2);
    Absorbtion = pow4(Absorbtion * 2.0);

    mediump vec3 CloudColorRaw = (SKY_GROUND * 2.0 + SunGlare);
    mediump vec3 CloudColor = CloudColorRaw * 0.25 / PI;

    mediump float VdotL = dot(ViewPosN, sunOrMoonPosN);
    mediump float MiePhase = max(xlf_phase(VdotL, 0.7) * 1.5, 1.0 / PI);
    CloudColor += SUN_DIRECT * MiePhase * exp(-Absorbtion * DENSITY);

    #ifdef IS_IRIS
    if (lightningBoltPosition.w > 0.0) {
        CloudColor += vec3(1.0) * exp(-DENSITY * distance(lightningBoltPosition.xz / far, PlayerPosN.xz) * 4.0);
    }
    #endif

    return SkyColor * Transmittance + CloudColor * Noise * DENSITY;
                        }

                        // Sky blending for Overworld
                        mediump vec3 get_sky(mediump vec3 ViewPosN, mediump vec3 SunGlare) {
                            mediump float upDot = dot(ViewPosN, gbufferModelView[1].xyz) + 0.1;
                            mediump vec3 MixedColor = mix(SKY_TOP, SKY_GROUND + SunGlare, fogify(max(upDot, 0.0), 0.03));
                            return MixedColor;
                        }

                        // Star field
                        mediump float get_stars(mediump vec3 PlayerPos) {
                            mediump vec3 StarCoord = PlayerPos / (PlayerPos.y + length(PlayerPos.xz));
                            StarCoord.x += frameTimeCounter * 0.001;
                            const mediump float ACTUAL_STAR_SIZE = STAR_SIZE * 512.0;
                            StarCoord = floor(StarCoord * ACTUAL_STAR_SIZE) / ACTUAL_STAR_SIZE;

                            mediump float Visibility = smoothstep(0.0, 0.1, StarCoord.y);
                            #ifdef DIMENSION_OVERWORLD
                            Visibility *= nightStrength;
                            #endif

                            return max(0.0, random(StarCoord.xz) - 0.996) * 50.0 * Visibility * STAR_STRENGTH;
                        }

                        // End sky / aurora
                        mediump vec3 get_end_sky(mediump vec3 ViewPosN, mediump vec3 PlayerPosN) {
                            const mediump vec3 SkyT  = to_linear(vec3(f_END_SKY_T_R, f_END_SKY_T_G, f_END_SKY_T_B));
                            const mediump vec3 SkyG1 = to_linear(vec3(f_END_AURORA1_R, f_END_AURORA1_G, f_END_AURORA1_B));
                            const mediump vec3 SkyG2 = to_linear(vec3(f_END_AURORA2_R, f_END_AURORA2_G, f_END_AURORA2_B));

                            mediump float upDot = dot(ViewPosN, gbufferModelView[1].xyz);
                            mediump float DistFromFlash = distance(PlayerPosN.xz, normalize(to_player_pos(endFlashPosition)).xz);
                            mediump float BoostFromFlash = (1.0 + max(0.0, 5.0 - DistFromFlash * 8.0) * endFlashIntensity);

                            mediump vec2 RotPos1 = rotate(PlayerPosN.xz, frameTimeCounter * 0.02);
                            mediump vec2 RotPos2 = rotate(PlayerPosN.xz, -frameTimeCounter * 0.007);

                            mediump float Noise1 = fbm_fast(RotPos1 * 160.0, 2);
                            mediump float Noise2 = fbm_fast(RotPos2 * 280.0, 2);
                            mediump float VerticalFactor = 1.0 - abs(upDot);
                            mediump vec3 SkyG = (SkyG1 * Noise1 + SkyG2 * Noise2) * VerticalFactor;

                            SkyG *= BoostFromFlash;
                            mediump vec3 Final = SkyT + SkyG * fogify(upDot + 0.2, 0.05);
                            Final *= max(1.0 - fogify(max(upDot + 0.2, 0.0), 0.02), 0.01);

                            return Final;
                        }

                        // Main sky selection
                        mediump vec3 get_sky_main(mediump vec3 ViewPosN, mediump vec3 PlayerPosN, mediump vec3 SunGlare) {
                            #ifdef DIMENSION_OVERWORLD
                            mediump vec3 SkyColor = get_sky(ViewPosN, SunGlare);
                            #elif defined DIMENSION_END
                            mediump vec3 SkyColor = get_end_sky(ViewPosN, PlayerPosN);
                            #else
                            mediump vec3 fogColorL = to_linear(fogColor.rgb) + 1e-6;
                            mediump vec3 SkyColor = mix(fogColorL, normalize(fogColorL), 0.4) / 3.0;
                            #endif

                            return SkyColor;
                        }
