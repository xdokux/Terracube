#include "/lib/all_the_libs.glsl"

flat in vec3 LightColorDirect; // This needs to be initialized in the vertex stage of the pass

#include "/generic/water.glsl"
#include "/generic/shadow/main.glsl"
#include "/generic/shadow/vl.glsl"
#include "/generic/sky.glsl"
#include "/generic/fog.glsl"
#include "/generic/clouds.glsl"
#include "/generic/post/taa.glsl"

in vec2 texcoord;

flat in vec3 LightPosFlare;

float get_flare_dist(vec2 Coord, const float SCALE) {
    vec2 d = Coord + LightPosFlare.xy * SCALE;
    d.x *= aspectRatio;
    return length(d);
}

float circle_flare(vec2 Coord, const float SCALE, const float SIZE) {
    float Dist = get_flare_dist(Coord, SCALE);

    return pow4(clamp(1 - Dist / SIZE, 0, 1));
}

float ring_flare(vec2 Coord, const float SCALE, const float SIZE) {
    float Dist = get_flare_dist(Coord, SCALE);

    Dist = abs(SIZE - Dist);
    return pow4(clamp(1 - Dist / SIZE, 0, 1));
}

float hollow_flare(vec2 Coord, const float SCALE, const float SIZE) {
    float Dist = get_flare_dist(Coord, SCALE);

    Dist /= SIZE;
    return (1 - smoothstep(0.8, 1.0, Dist)) * Dist;
}

vec3 lens_flare() {
    if(dataBuf.SunVisibility < 1e-6) return vec3(0);

    vec2 Coord = texcoord - 0.5;

    vec3 Color = vec3(0);

    // Streaks
    vec2 d = LightPosFlare.xy - Coord;
    d.x *= aspectRatio;
    d = abs(d);
    float Falloff = 1 - smoothstep(0.0, 0.5, d.x);
    Color += (1-smoothstep(0.0, 0.02, d.y)) * Falloff * 0.005;
    
    // float ang = atan(d.x, d.y);
    // float Dist = length(d);
    // float Noise = texture(noisetex, vec2(sin(ang*0.5+LightPosFlare.x)*2 - cos(ang+LightPosFlare.y)*1, 0)/255).r;
    // Color.rgb += pow4(sin(Noise)) * pow(max(0, 1-Dist), 32);
    

    // Circle things
    Color += circle_flare(Coord, -0.25, 0.02) * 0.03;

    Color.r += circle_flare(Coord, 0.68, 0.07) * 0.01;
    Color.g += circle_flare(Coord, 0.7, 0.07) * 0.01;
    Color.b += circle_flare(Coord, 0.72, 0.07) * 0.04;

    Color.r += circle_flare(Coord, 0.92, 0.07) * 0.005;
    Color.b += circle_flare(Coord, 0.94, 0.07) * 0.02;

    // Other circle things
    Color += hollow_flare(Coord, -0.1, 0.03) * 0.002;

    Color.r += hollow_flare(Coord, 0.57, 0.1) * 0.001;
    Color.g += hollow_flare(Coord, 0.58, 0.1) * 0.002;
    Color.b += hollow_flare(Coord, 0.59, 0.1) * 0.004;

    Color.g += hollow_flare(Coord, 1.5, 0.2) * 0.002;
    Color.b += hollow_flare(Coord, 1.52, 0.2) * 0.006;

    // Big outer ring
    Color.b += ring_flare(Coord, 2.0, 0.5) * 0.008;

    // Halo around the sun
    Color.r += ring_flare(Coord, -1, 0.15) * 0.002;
    Color.g += ring_flare(Coord, -1, 0.16) * 0.003;
    Color.b += ring_flare(Coord, -1, 0.17) * 0.006;
    
    return Color * dataBuf.SunVisibility * LightColorDirect;
}

/* RENDERTARGETS:0,6,7,10 */
layout(location = 0) out vec4 Color;
layout(location = 1) out vec4 TemporalClouds;
layout(location = 2) out vec4 TemporalVl;
layout(location = 3) out vec4 ArmorGlint;

void main() {
    Color = texture(colortex0, texcoord);
    bool IsDH;
    float Depth = get_depth(texcoord, IsDH);
    Positions Pos = get_positions(texcoord, Depth, IsDH, true);
    float Dither = dither(gl_FragCoord.xy, true);

    vec3 SkyColor = get_sky(Pos.ViewN, false, Pos.PlayerN.y); 
    #ifdef DIMENSION_OVERWORLD
        #ifdef CLOUDS
            TemporalClouds = temporal_upscale_clouds(Pos.Screen, IsDH, ivec2(gl_FragCoord.xy), Pos.Player, Pos.PlayerN, colortex6);
            Color.rgb = blend_vl(Color.rgb, TemporalClouds);
        #endif

        #if VL_OVERWORLD_MODE == 1
            TemporalVl = temporal_upscale_vl(Pos.Screen, IsDH, ivec2(gl_FragCoord.xy), Pos.Player);

            // Super silly transmittance approx
            const float MtoRratio = (0.659 + 1.156) / 0.939; // For len = 500m
            vec3 OpticalDepth = BETA_M_E * MtoRratio + BETA_R_E / MtoRratio;
            vec3 T = exp(log(TemporalVl.a) / dot(OpticalDepth, vec3(0.33)) * OpticalDepth);
            Color.rgb = blend_vl(Color.rgb, mat2x3(TemporalVl.rgb, T));

            float FogAmount = clamp(fogAmount / 5, 0, 1);
            vec4 VlScaled = vec4(TemporalVl.rgb * mix(1.1, 1.4, FogAmount), TemporalVl.a * mix(0.82, 0.5, FogAmount));
            T = exp(log(VlScaled.a) / dot(OpticalDepth, vec3(0.33)) * OpticalDepth);
            SkyColor = blend_vl(SkyColor.rgb, mat2x3(VlScaled.rgb, T));
        #endif
    #endif  

    mat2x3 VlResult = do_vl(vec3(0), Pos.Player, Pos.PlayerN, Pos.Screen, Dither, LightColorDirect, IsDH, VL_SAMPLES, VL_OVERWORLD_RT, VL_OVERWORLD_RT);
    Color.rgb = blend_vl(Color.rgb, VlResult);
    #if VL_OVERWORLD_MODE == 0
        SkyColor = blend_vl(SkyColor.rgb, VlResult);
    #endif

    Color.rgb = get_fog_main(Pos.Player, Color.rgb, SkyColor, Pos.Screen.z);

    
    Color.rgb = purkinje_effect(Color.rgb);

    #if (defined LENS_FLARE) && (defined DIMENSION_OVERWORLD)
    Color.rgb += lens_flare() * LENS_FLARE_STRENGTH;
    #endif

    ArmorGlint = vec4(0,0,0,1); // Needs to be cleared for bloom
}
