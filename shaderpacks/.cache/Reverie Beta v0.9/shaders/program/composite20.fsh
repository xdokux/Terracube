#include "/lib/all_the_libs.glsl"

in vec2 texcoord;
in vec2 BloomTilePos;

#include "/generic/post/bloom.glsl"

/* RENDERTARGETS:0 */
layout(location = 0) out vec4 Color;

void main() {
    Color = texture(colortex0, texcoord);

    #ifdef BLOOM
    float Offset = 0;
    vec3 FinalBloom = blur6x6(colortex10, BloomTilePos).rgb;

    float WeatherColor = texture(colortex5, texcoord).g * 0.5;

    Color.rgb += FinalBloom * (BLOOM_STRENGTH + float(isEyeInWater == 1) * 0.5 + 0.2 * (rainStrength * isOutdoorsSmooth) + WeatherColor);
    #endif
}
