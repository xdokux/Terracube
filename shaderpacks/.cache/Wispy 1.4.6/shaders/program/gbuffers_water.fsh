#include "/lib/all_the_libs.glsl"

uniform sampler2D lightmap;
uniform sampler2D gtexture;

varying vec2 texcoord;
varying vec4 glcolor;
varying vec3 MixedLights;
flat varying float material;

vec3 fast_normalize(vec3 v) {
    return v * inversesqrt(max(dot(v, v), 1e-6));
}

void main() {
    vec4 Color = texture2D(gtexture, texcoord) * glcolor;

    if (abs(material - 10002.0) < 0.1) {
        #ifdef DIMENSION_OVERWORLD
        const vec3 deepBlue = vec3(0.02, 0.04, 0.2025);
        Color.rgb = deepBlue;
        Color.a = 0.25;

        if (isEyeInWater == 1) {
            vec2 ScreenPos = gl_FragCoord.xy * resolutionInv;
            float TerrainDepth = texture2D(depthtex1, ScreenPos).x;
            float WaterDepth = gl_FragCoord.z;
            float DepthDiff = linearize_depth(TerrainDepth) - linearize_depth(WaterDepth);
            float fogFactor = clamp(DepthDiff * (1.0/48.0), 0.0, 1.0) * WATER_FOG_STRENGTH;
            Color.a = min(Color.a + fogFactor, 1.0);
        }
        #elif defined DIMENSION_END
        const vec3 endWater = vec3(0.05, 0.0, 0.1);
        Color.rgb = endWater;
        Color.a = 0.4;
        #else
        const vec3 netherWater = vec3(0.15, 0.02, 0.0);
        Color.rgb = netherWater;
        Color.a = 0.4;
        #endif

    } else {
        float baseAlpha = 0.3;
        Color.a = mix(baseAlpha, 1.0, Color.a);
    }

    Color.rgb *= MixedLights;

    #ifdef BORDER_FOG
    vec3 ScreenPosFog = vec3(gl_FragCoord.xy * resolutionInv, gl_FragCoord.z);
    vec3 ViewPos = to_view_pos(ScreenPosFog, false);
    float dist = length(ViewPos);

    vec3 SkyFogColor;
    #if defined DIMENSION_END
    SkyFogColor = vec3(0.05, 0.0, 0.1);
    #elif defined DIMENSION_NETHER
    SkyFogColor = to_linear(fogColor.rgb) * 0.2;
    #else
    SkyFogColor = to_linear(fogColor.rgb);
    #endif

    float fogFactor = 1.0 - clamp(exp(-dist * (fogAmount * 0.0015)), 0.0, 1.0);

    Color.rgb = mix(Color.rgb, SkyFogColor, fogFactor);
    #endif

    gl_FragData[0] = Color;
}
