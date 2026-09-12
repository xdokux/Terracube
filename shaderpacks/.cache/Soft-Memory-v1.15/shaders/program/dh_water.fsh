#define DH_TERRAIN

#include "/lib/all_the_libs.glsl"
uniform sampler2D lightmap;
uniform sampler2D gtexture;

varying vec2 texcoord;
varying vec4 glcolor;
varying vec2 LightmapCoords;

#include "/global/lighting.fsh"
#include "/global/sky.glsl"
#include "/global/fog.glsl"

flat varying mat3 TBN;
#include "/global/water.glsl"

vec4 get_translucent_basic(vec3 TweakedLM, vec3 ViewPos,vec2 screen) {
    vec4 Color = glcolor * texture2D(gtexture, texcoord);
    
    if (Color.a < 0.1) {
        discard;
    }

    
    vec3 PlayerPos = to_player_pos(ViewPos);
    
    #ifdef DH_NOISE
        Color.rgb = dh_noise(PlayerPos, Color.rgb);
    #endif

    Color.rgb = to_linear(Color.rgb);
    Color.rgb *= TweakedLM;
    

    return Color;
}

/* DRAWBUFFERS:0 */

void main() {

    vec3 ScreenPos = vec3(gl_FragCoord.xy*resolutionInv, gl_FragCoord.z);
    vec3 ViewPos = to_view_pos(ScreenPos, true);
    vec3 PlayerPos = to_player_pos(ViewPos);


    float Dither = bayer8(gl_FragCoord.xy);
    if (!transition_to_dh(PlayerPos, true, Dither)) {
        discard;
        return;
    }

    float Depth = texture2D(depthtex0, ScreenPos.xy).x;

    if(Depth < 1) {
        discard; return;
    }
     vec3 worldPos = to_player_pos(ViewPos) + cameraPosition;

    vec3 TweakedLM = tweak_lightmap(worldPos);

    vec4 Color;
    #ifndef FANCY_WATER
    Color = get_translucent_basic(TweakedLM, ViewPos,ScreenPos.xy);
    #else
    if(material == 10002) {
        // --- POOLCORE LOGIC FOR DH WATER ---
        
        // 1. Force Base Color (Electric Cyan)
        Color = vec4(0.05, 0.1, 0.9, 0.45); 
        Color.rgb = to_linear(Color.rgb);
        
        // 2. Calculate Brightness (Strip Color)
        float brightness = dot(TweakedLM, vec3(0.33));
        
        // 3. CLAMP BRIGHTNESS (Prevents White Water at Noon)
        // Limits sun intensity to 0.9 max so color remains visible.
        brightness = clamp(brightness, 0.5, 0.9);

        // 4. Create Custom Lighting (Cyan/White mix)
        vec3 poolLight = vec3(0.1, 0.1, 1.0);
        
        // 5. Apply Lighting & Boost
        Color.rgb *= poolLight * 1.3; 
        
        vec4 BaseColor = Color; 
        
        // Note: The 'true' at the end tells get_fancy_water this is Distant Horizons
        Color = get_fancy_water(ScreenPos, ViewPos, BaseColor, LightmapCoords.y, TBN, true,lightmap,texcoord);
    }
    else {
        Color = get_translucent_basic(TweakedLM, ViewPos,ScreenPos.xy);
    }
    #endif
     float cloudTransmittance = 1.0;
    vec3 ViewPosN = normalize(ViewPos);
    vec3 SkyColor = get_sky_main(ViewPosN, normalize(PlayerPos), get_sun_glare(dot(ViewPosN, sunPosN)),cloudTransmittance);
    vec2 lmcoord = texture2D(lightmap, texcoord).rg;

    Color.rgb = get_fog_main(PlayerPos, Color.rgb, gl_FragCoord.z, SkyColor, lmcoord.y);
    gl_FragData[0] = Color;

}