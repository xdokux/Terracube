/* RENDERTARGETS: 0,12 */
#include "/lib/all_the_libs.glsl"
uniform sampler2D lightmap;
uniform sampler2D gtexture;

varying vec2 texcoord;
varying vec4 glcolor;
varying vec2 LightmapCoords;

#include "/global/lighting.fsh"
#include "/global/sky.glsl"
#include "/global/fog.glsl"

varying mat3 TBN;
#include "/global/water.glsl"

vec4 get_translucent_basic(vec3 TweakedLM, vec3 ViewPos,vec2 screen) {
    vec4 Color = glcolor * texture2D(gtexture, texcoord);
    Color.rgb = to_linear(Color.rgb);
    if (Color.a < 0.1) {
        discard;
    }
    Color.rgb *= TweakedLM;

    

    return Color;
}



void main() {
    vec3 ScreenPos = vec3(gl_FragCoord.xy*resolutionInv, gl_FragCoord.z);
    vec3 ViewPos = to_view_pos(ScreenPos, false);
    vec3 PlayerPos = to_player_pos(ViewPos);
    #ifdef DISTANT_HORIZONS
    float Dither = bayer8(gl_FragCoord.xy);
    if (transition_to_dh(PlayerPos, false, Dither)) {
        discard;
        return;
    }
    #endif
    vec3 worldPos = to_player_pos(ViewPos) + cameraPosition;
    vec3 TweakedLM = tweak_lightmap(worldPos);

    vec4 Color;
    #ifndef FANCY_WATER
    Color = get_translucent_basic(TweakedLM, ViewPos,ScreenPos.xy);
    #else
    if(material == 10002) {
        // --- POOLCORE BASE ---
        Color = vec4(0.05, 0.9, 1.0, 0.45); 
        Color.rgb = to_linear(Color.rgb);
        
        // --- POOLCORE LIGHTING FIX ---
        // 1. Get brightness
        float brightness = dot(TweakedLM, vec3(0.33));
        
        // 2. CLAMP IT (This fixes the White Water!)
        // We stop brightness at 0.9 so it never hits 1.0 (Pure White)
        brightness = clamp(brightness, 0.5, 0.9);

        // 3. Create Cyan Lighting
        vec3 poolLight = vec3(0.6, 0.8, 1.0) * brightness;
        if(isEyeInWater ==0){
        Color.rgb *= poolLight * 0.3; 
        }
        vec4 BaseColor = Color; 
        Color = get_fancy_water(ScreenPos, ViewPos, BaseColor, LightmapCoords.y, TBN, false,lightmap,texcoord);
        gl_FragData[1] = vec4(1.0,0.0,0.0,1.0);
    }
    else {
        Color = get_translucent_basic(TweakedLM, ViewPos,ScreenPos.xy);
        gl_FragData[1] = vec4(0.0,0.0,0.0,1.0);
    }
    #endif

    float cloudTransmittance = 1.0;

    vec3 ViewPosN = normalize(ViewPos);
    vec3 SkyColor = get_sky_main(ViewPosN, normalize(PlayerPos), get_sun_glare(dot(ViewPosN, sunPosN)),cloudTransmittance);
    vec2 lmcoord = texture2D(lightmap, texcoord).rg;

    Color.rgb = get_fog_main(PlayerPos, Color.rgb, gl_FragCoord.z, SkyColor, lmcoord.y);


    gl_FragData[0] = Color;

}