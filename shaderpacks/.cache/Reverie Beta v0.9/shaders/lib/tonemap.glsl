float get_luminance(vec3 x) {
    return dot(x, vec3(0.2126, 0.7152, 0.0722));
}

vec3 reinhard(vec3 x) {
    return x / (1 + x);
}

vec3 reinhard_inv(vec3 x) {
    return x / (1 - x);
}

float reinhard(float x) {
    return x / (1 + x);
}

float reinhard_inv(float x) {
    return x / (1 - x);
}

#include "tonemap/Reinhard_Jodie.glsl"
#include "tonemap/ACES.glsl"
#include "tonemap/Uncharted2.glsl"
#include "tonemap/agx_minimal.glsl"

vec3 apply_tonemap(vec3 x) {
    #if TONEMAP_OPERATOR == 0
    return reinhard_jodie(x);
    #elif TONEMAP_OPERATOR == 1
    return ACESFitted(x);
    #elif TONEMAP_OPERATOR == 2
    return uncharted2_filmic(x);
    #elif TONEMAP_OPERATOR == 3
    return agx_tonemapping(x);
    #else
    return x;
    #endif
}

vec3 apply_saturation(vec3 Color, float Sat) {
    float luminance = get_luminance(Color);
    return mix(vec3(luminance), Color, Sat);
}

vec3 apply_vibrance(vec3 color, float intensity) {
    float mn = min(color.r, min(color.g, color.b));
    float mx = max(color.r, max(color.g, color.b));
    float sat = (1.0 - clamp(mx - mn, 0, 1)) * clamp(1.0 - mx, 0, 1) * get_luminance(color) * 5.0;
    vec3 lightness = vec3((mn + mx) * 0.5);

    return mix(color, mix(lightness, color, intensity), sat);
}

vec3 apply_contrast(vec3 color, float contrast) {
    return (color - 0.5) * contrast + 0.5;
}

vec3 purkinje_effect(vec3 Color) {
    vec3 ColorXYZ = rgb_to_xyz(Color);
    float ScotopicLuminance = ColorXYZ.y * (1.33 * (1.0 + (ColorXYZ.y + ColorXYZ.z) / max(ColorXYZ.x, 0.01)) - 1.68);
    vec3 NightColor = ScotopicLuminance * PurkinjeTint;

    float BlendFactor = 1 - smoothstep(0.0, 0.05, get_luminance(Color));
    vec3 FinalColor = Color * mix(vec3(1), NightColor, BlendFactor * PURKINJE_EFFECT_STRENGTH);
    return FinalColor;
}

vec3 film_grain(vec3 Color, vec2 Pos) {
    const float SIZE = 1.0 / (512 * FILM_GRAIN_SIZE);
    float framemod60 = floor(frameTimeCounter * 60); // Grain becomes less apparent at high fps without this
    vec3 GrainColor = (texture(noisetex, fract(Pos.xy * SIZE + framemod60 * 1.61)).rgb - 0.5) * FILM_GRAIN_STRENGTH * 0.1;
    float BlendFactor = 1 - smoothstep(0.0, FILM_GRAIN_MAX_BRIGHTNESS, get_luminance(Color));
    return Color + GrainColor * BlendFactor;
}


vec3 rgb_to_hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz),
                 vec4(c.gb, K.xy),
                 step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r),
                 vec4(c.r, p.yzx),
                 step(p.x, c.r));

    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(
        abs(q.z + (q.w - q.y) / (6.0 * d + e)), // Hue
        d / (q.x + e),                          // Saturation
        q.x                                     // Value
    );
}

vec3 hsv_to_rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}