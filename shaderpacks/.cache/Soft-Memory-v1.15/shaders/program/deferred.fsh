#include "/lib/all_the_libs.glsl"


#include "/global/sky.glsl"
#include "/global/fog.glsl"
#include "/global/post/ssao.glsl"
#include "/global/water.glsl"
#include "/global/post/godrays.glsl"
#include "/global/post/BlockReflection.glsl"

uniform sampler2D lightmap;

// Sky, Clouds, etc
varying vec2 texcoord;
varying vec2 LightmapCoords;

/* DRAWBUFFERS:0 */

void main() {
    vec4 Color = texture2D(colortex0, texcoord);
    bool IsDH;
    float Depth = get_depth(texcoord, IsDH);
    vec3 ScreenPos = vec3(texcoord, Depth);
    vec3 ViewPos = to_view_pos(ScreenPos, IsDH);

    vec3 BlockNormal = texture2D(colortex9, texcoord).xyz * 2.0 - 1.0;
    vec3 PlayerPos = mat3(gbufferModelViewInverse) * ViewPos;

    vec3 ViewPosN = normalize(ViewPos);
    vec3 PlayerPosN = normalize(PlayerPos);

    float VdotL = dot(ViewPosN, sunPosN);
    vec3 SunGlare = get_sun_glare(VdotL);

    vec2 lmcoord = texture2D(lightmap, texcoord).rg;

    float cloudTransmittance = 1.0;
   
    vec3 SkyColor = get_sky_main(ViewPosN, PlayerPosN, SunGlare,cloudTransmittance);
    
    
    vec3 BaseFogColor = get_sky(ViewPosN, SunGlare); 


    float Dither = dither(gl_FragCoord.xy);

    vec3 dPdx = dFdx(ViewPos);
    vec3 dPdy = dFdy(ViewPos);
    vec3 crossP = cross(dPdx, dPdy);
    vec3 viewNormal = length(crossP) > 0.0001 ? normalize(crossP) : vec3(0.0, 1.0, 0.0);
    vec3 WorldNormal = mat3(gbufferModelViewInverse) * viewNormal;


    // --- 1. RENDER SKY / BACKGROUND ---
    if (Depth >= 1.0) {
        #ifndef CUSTOM_SKYBOXES
            #ifndef DIMENSION_OVERWORLD
                Color = vec4(0, 0, 0, 1);
            #elif defined ROUND_SUN
                SkyColor += round_sun(ViewPosN, sunPosN, PlayerPosN) * cloudTransmittance;
            #endif

            #ifdef DEBUG_OVERRIDE_SKY
                Color.rgb = SkyColor;
            #else
                Color.rgb += SkyColor;
            #endif

            if (PlayerPos.y > 0.0) {
                #if defined DIMENSION_OVERWORLD || defined DIMENSION_END
                    Color.rgb += get_stars(PlayerPos) * cloudTransmittance;
                    Color.rgb += get_shooting_stars(PlayerPos) * cloudTransmittance;
                #endif

                #ifdef DIMENSION_END
                    #ifdef SHOOTING_STARS
                        Color.rgb += get_shooting_stars_end(PlayerPos);
                    #endif
                #endif

                vec3 viewDir = normalize(PlayerPos);
                float horizon = smoothstep(-0.05, 0.15, viewDir.y);
                //Color.rgb += vec3(0.10, 0.06, 0.03) * horizon * ( 1.0 + rainStrength);

                #ifdef DIMENSION_OVERWORLD
                    #ifdef FANCY_CLOUDS
                        Color.rgb = get_clouds(ViewPosN, PlayerPos, PlayerPosN, SunGlare, Color.rgb);
                    #endif

                    Color.rgb += get_rainbow(PlayerPosN);

                    #ifdef AURORA_BOREALIS
                        Color.rgb += get_aurora(PlayerPosN, Dither) * cloudTransmittance;
                    #endif
                #endif
            }
        #endif
    } 
    // --- 2. RENDER BLOCK EFFECTS ---
    else if (Depth >= 0.56) { // Skip sky and hand
        
        #ifdef SSAO
            Color.rgb = ssao(Color.rgb, ViewPos, Dither, IsDH);
        #endif

        #ifdef WET_REFLECTIONS
            vec4 SmoothData = texture2D(colortex8, texcoord);
            float Smoothness = SmoothData.r;
            float F0 = SmoothData.g; 

            if (F0 > 0.1) {
                vec3 ReflectedVec = reflect(ViewPosN, BlockNormal);
                float Dist = dot(ReflectedVec, sunPosN);
                float Fresnel = schlick(ViewPosN, BlockNormal) * LightmapCoords.y;

                vec3 reflectionColor = ssr_Block(ReflectedVec, Dist, ViewPos, Fresnel, WorldNormal.y, IsDH, lightmap, texcoord, LightmapCoords.y, Color.rgb);
                
                Color.rgb = mix(Color.rgb, reflectionColor, F0 * ((rainStrength + 0.2) * 3.0));
            }
        #endif
    }

    if (Depth >= 0.56) { // Skip JUST the hand
        
 
        Color.rgb = get_fog_main(PlayerPos, Color.rgb, Depth, BaseFogColor,lmcoord.y);

        #if defined DIMENSION_OVERWORLD && defined GODRAYS2D
            Color.rgb += godrays(ScreenPos, Dither, IsDH);
        #endif
    }

    gl_FragData[0] = Color;
}