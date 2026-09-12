varying vec2 LightmapCoords;
varying vec2 texcoord;
varying vec4 glcolor;

attribute vec4 mc_Entity;
attribute vec2 mc_midTexCoord;

flat varying float material;
varying mediump vec3 MixedLights;
flat varying vec3 Normal;

vec3 ViewPos;

#include "/global/light_colors.vsh"
#include "/global/sky.glsl"

void init_generic() {
    init_colors();

    gl_Position = ftransform();
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    glcolor = gl_Color;

    const float lightmapScale = 1.06667;
    const float lightmapOffset = 0.0625;
    LightmapCoords = clamp((gl_TextureMatrix[1] * gl_MultiTexCoord1).xy * lightmapScale - lightmapOffset, 0.001, 0.999);

    material = mc_Entity.x;
    ViewPos = (gl_ModelViewMatrix * gl_Vertex).xyz;

    vec3 NormalA;
    if (material >= 10000.0) {
        NormalA = gbufferModelView[1].xyz;
        float needsHalf = step(10003.5, material) * step(material, 10005.5);
        NormalA *= mix(1.0, 0.5, needsHalf * step(mc_midTexCoord.t, gl_MultiTexCoord0.t));
    } else {
        Normal = normalize(gl_NormalMatrix * gl_Normal);
        NormalA = Normal;
    }

    // Determine light color based on block ID
    vec3 TorchColor;
    #ifdef DIMENSION_OVERWORLD
    if (material >= 10010.0 && material < 10011.0) {
        // Warm lights (torches, fire, lava)
        TorchColor = vec3(1.3, 0.9, 0.55);
    } else if (material >= 10011.0 && material < 10012.0) {
        // Cool lights (soul fire, end rods)
        TorchColor = vec3(0.4, 0.7, 1.2);
    } else if (material >= 10012.0 && material < 10013.0) {
        // Neutral lights (glowstone, shroomlight)
        TorchColor = vec3(1.0, 1.0, 0.85);
    } else if (material >= 10013.0 && material < 10014.0) {
        // Purple lights (amethyst, portals)
        TorchColor = vec3(1.0, 0.5, 1.2);
    } else if (material >= 10014.0 && material < 10015.0) {
        // Sculk lights (cyan)
        TorchColor = vec3(0.3, 0.9, 1.0);
    } else {
        // Default warm
        TorchColor = vec3(f_LM_RED, f_LM_GREEN, f_LM_BLUE);
    }
    #elif defined DIMENSION_END
    TorchColor = vec3(1.0, 0.6, 0.9);
    #else
    TorchColor = vec3(1.0, 1.0, 1.0);
    #endif
    TorchColor *= TorchColor;

    #ifndef DIMENSION_OVERWORLD
    LightmapCoords.y = 0.999;
    #endif

    #ifndef DIMENSION_NETHER
    float NdotL = 0.0;
    float NdotU = 0.0;

    #ifdef DIMENSION_END
    NdotL = max(dot(NormalA, gbufferModelView[1].xyz), 0.0);
    #else
    NdotL = max(dot(NormalA, sunOrMoonPosN), 0.0);
    NdotU = clamp(dot(gbufferModelView[1].xyz, NormalA), -1.0, 1.0);
    SUN_AMBIENT = mix(SUN_AMBIENT, mix(SKY_GROUND, SKY_TOP, NdotU * 0.25 + 0.25), 0.5);
    #endif

    float shadowTransition = smoothstep(0.80, 0.99, LightmapCoords.y);
    SUN_AMBIENT += SUN_DIRECT * NdotL * clamp(shadowTransition, 0.01, 0.99);
    #endif

    float lmx = LightmapCoords.x * LightmapCoords.x;

    vec3 ambientFloor = vec3(0.02);

    MixedLights = TorchColor * lmx + mix(ambientFloor, SUN_AMBIENT, clamp(LightmapCoords.y, 0.0, 1.0));
    MixedLights *= clamp(1.0 - darknessLightFactor, 0.05, 1.0);
}
