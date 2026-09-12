#include "/lib/all_the_libs.glsl"
varying vec2 texcoord;

#include "/global/post/bloom.glsl"

/* DRAWBUFFERS:0 */

void main() {
    vec4 Color = texture2D(colortex0, texcoord);

    #ifdef BLOOM
    float Offset = 0;
    vec3 FinalBloom = vec3(0);
    float TotalWeight = 0.0;
    for (int i = 2; i < 5; i++) {
        // Weight larger blur passes more for softer, dreamier bloom
        float Weight = 1.0 / float(i);
        FinalBloom += texture2D(colortex1, texcoord / exp2(i) + Offset).xyz * Weight;
        TotalWeight += Weight;
        Offset += 1 / exp2(i);
    }
    FinalBloom /= TotalWeight;

    float BloomLuminance = get_luminance(FinalBloom);
    // Improved bloom curve: softer for low values, stronger for high
    float BloomFactor = pow(BloomLuminance, BLOOM_CURVE) * (1.0 + BloomLuminance * 0.5);
    BloomFactor += 0.2 * rainStrength * isOutdoorsSmooth;
    vec2 EdgeFade = smoothstep(0.02, 0.05, texcoord) * (1 - smoothstep(0.95, 0.98, texcoord));
    BloomFactor *= EdgeFade.x * EdgeFade.y;

    // Preserve color hue better during bloom mixing
    Color.rgb = mix(Color.rgb, FinalBloom, clamp(BloomFactor * BLOOM_STRENGTH, 0.0, 0.7));
    #endif

    gl_FragData[0] = Color;
}
