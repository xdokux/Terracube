varying vec2 LightmapCoords;
varying vec2 texcoord;
varying vec4 glcolor;
attribute vec4 mc_Entity;
attribute vec2 mc_midTexCoord;
flat varying float material;
varying vec3 MixedLights;
varying vec3 Normal;
varying vec3 ViewPos;

varying vec2 vMidCoord;
varying vec2 vTileSize;


#include "/global/light_colors.vsh"

void init_generic() {
    init_colors();

    gl_Position = ftransform();
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;

    vMidCoord = mc_midTexCoord;
    vTileSize = abs(gl_MultiTexCoord0.xy - mc_midTexCoord) * 2.0;

    LightmapCoords = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    LightmapCoords = max(LightmapCoords * 1.06667 - 0.0625, 0);
    material = mc_Entity.x;

    ViewPos = (gl_ModelViewMatrix * gl_Vertex).xyz;

    Normal = normalize(gl_NormalMatrix * gl_Normal);
    vec3 NormalA;
    if (material == 10001 || material == 10004 || material == 10005 || material == 10006) {
        NormalA = gbufferModelView[1].xyz;
        // Make grass darker at the bottom. It looks better this way
        if (gl_MultiTexCoord0.t > mc_midTexCoord.t && (material == 10004 || material == 10005)) NormalA *= 0.5;
    }
    else {
        NormalA = Normal;
    }
    glcolor = gl_Color;

    #ifdef HANDHELD_LIGHTS
    float Dist = length(ViewPos);

    float HandheldLight = heldBlockLightValue;
    LightmapCoords.x = max(LightmapCoords.x, pow(max((HandheldLight - Dist) / 15.0, 0), 4.0 - HANDHELD_FALLOFF_CURVE * 1.5));
    #endif

    #ifdef LM_FLICKER
    LightmapCoords.x *= (1. - LM_FLICKER_STRENGTH) + texture2D(noisetex, vec2(frameTimeCounter / 4, 0)).r * LM_FLICKER_STRENGTH;
    #endif

    const vec3 TorchColor = to_linear(vec3(f_LM_RED, f_LM_GREEN, f_LM_BLUE));
    float MinLight = clamp(MIN_LIGHT_AMOUNT + screenBrightness * 0.1 - 0.1, 0, 0.05);
    MinLight = to_linear(MinLight);
    MinLight += nightVision / 3;

    #ifndef DIMENSION_OVERWORLD
    LightmapCoords.y = 1;
    #else
    float NdotU = clamp(dot(gbufferModelView[1].xyz, Normal), -1, 1);
    SUN_AMBIENT = mix(SUN_AMBIENT, mix(SKY_GROUND, SKY_TOP, NdotU * 0.25 + 0.25), 0.5);
    #endif

    #ifndef DIMENSION_NETHER
        
        #ifdef DIMENSION_END
            float NdotL = max(dot(NormalA, gbufferModelView[1].xyz), 0);
        #else
            float NdotL = max(dot(NormalA, sunOrMoonPosN), 0);
        #endif

    
        #ifdef IS_IRIS
            if(lightningBoltPosition.w > 0) {  
                float VdotLi = 1 - min(1, distance(lightningBoltPosition.xyz, to_player_pos(ViewPos)) * 0.01);
                vec3 LiBPN = normalize((player_view(lightningBoltPosition.xyz) - ViewPos));
                float NdotLi = max(0, dot(Normal, LiBPN)) * 0.8 + 0.2;
                SUN_AMBIENT += vec3(1) * NdotLi * VdotLi;
            }
        #endif

        SUN_AMBIENT += SUN_DIRECT * NdotL;
    #endif

    LightmapCoords.x = pow(LightmapCoords.x, 4.0001 - LM_FALLOFF_CURVE * 1.5);

    LightmapCoords.x = mix(LightmapCoords.x, LightmapCoords.x, LightmapCoords.y);
    #ifdef VOXELIZE
    MixedLights =  mix(vec3(MinLight), SUN_AMBIENT, LightmapCoords.y);
    #else
    MixedLights = TorchColor * LightmapCoords.x + mix(vec3(MinLight), SUN_AMBIENT, LightmapCoords.y);
    #endif
    MixedLights *= 1 - darknessLightFactor;
}
