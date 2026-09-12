#include "/lib/all_the_libs.glsl"

#undef PBR_NORMAL
#undef PBR_SPECULAR

#include "/global/gbuffers.fsh"

/* DRAWBUFFERS:0 */
layout(location = 0) out vec4 Color;

void main() {
        Color = texture(gtexture, texcoord) * glcolor;
        if (Color.a < 0.1) {
                discard;
        }
        Color.rgb = to_linear(Color.rgb);

        vec3 ScreenPos = vec3(gl_FragCoord.xy*resolutionInv, gl_FragCoord.z);
        vec3 PlayerPos = view_player(ViewPos, false);
        mat3 TBN = tbn_decode(Normal, Tangent);
        vec3 TweakedLM = tweak_lightmap(Color.rgb, PlayerPos, LightmapCoords, texcoord, ScreenPos, TBN, 0, 1);
        Color.xyz = TweakedLM;


        Color = vec4(apply_saturation(Color.rgb, 0.2), 0.15);

        // === Velocity: enhanced rain ===
        // Make rain particles look like motion-blurred streaks instead of
        // flat points. We stretch the alpha vertically (in screen space)
        // based on the rain density, giving the impression of fast-falling
        // droplets. Also brighten slightly so rain reads better against
        // dark storm skies.
        #ifdef HELIOS_RAIN_ENHANCE
        #ifdef HELIOS_RAIN_STREAKS
        {
                // Vertical streak factor: stretch the particle's effective
                // vertical extent. We do this by modulating alpha based on
                // the texcoord's distance from the vertical center.
                // (gbuffers_weather uses a small particle texture, so this
                // is a cheap per-pixel stretch.)
                float vertDist = abs(texcoord.y - 0.5) * 2.0;
                // Stretch: lower vertDist = more visible (longer streak).
                float stretch = 1.0 - smoothstep(0.3, 1.0, vertDist);
                Color.a *= mix(1.0, stretch, HELIOS_RAIN_STREAK_LENGTH * rainStrength);
                // Slight brightening so streaks pop against dark skies.
                Color.rgb *= 1.0 + 0.15 * HELIOS_RAIN_STREAK_LENGTH * rainStrength;
        }
        #endif
        #endif
}
