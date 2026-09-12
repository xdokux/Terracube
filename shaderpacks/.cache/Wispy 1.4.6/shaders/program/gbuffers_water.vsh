#include "/lib/all_the_libs.glsl"
#include "/global/lighting.vsh"

void main() {
    init_generic();
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vec4 BaseColor;
    float waterContribution;
    #ifdef DIMENSION_OVERWORLD
    BaseColor = vec4(f_WATER_RED, f_WATER_GREEN, f_WATER_BLUE, f_WATER_ALPHA);
    waterContribution = f_BIOME_WATER_CONTRIBUTION;
    #elif defined DIMENSION_END
    BaseColor = vec4(0.15, 0.05, 0.25, 0.5);
    waterContribution = 0.0;
    #else
    BaseColor = vec4(0.5, 0.1, 0.05, 0.6);
    waterContribution = 0.0;
    #endif
    vec3 finalRGB = mix_preserve_c1lum(BaseColor.rgb, to_linear(gl_Color.rgb), waterContribution);
    glcolor = vec4(finalRGB, BaseColor.a);
}
