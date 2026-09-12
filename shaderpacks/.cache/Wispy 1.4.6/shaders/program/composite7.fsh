#include "/lib/all_the_libs.glsl"
varying vec2 texcoord;
varying vec2 BloomTilePos;
#include "/global/post/bloom.glsl"

/* DRAWBUFFERS:0 */

void main() {
    vec4 Color = texture2D(colortex0, texcoord);

    #ifdef BLOOM  // Keep original define to match settings
    float Offset = 0;
    vec3 FinalBloom = blur3x3(colortex1, BloomTilePos).rgb;
    FinalBloom /= 3;

    float BloomFactor = get_luminance(FinalBloom) * BLOOM_CURVE + (1 - BLOOM_CURVE);
    BloomFactor += 0.2 * rainStrength * isOutdoorsSmooth;

    BloomFactor /= 1.667; // Reminder: remove this next major version

    Color.rgb = mix(Color.rgb, FinalBloom, BloomFactor * BLOOM_STRENGTH);
    #endif

    gl_FragData[0] = Color;
}
