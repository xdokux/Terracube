#include "/lib/all_the_libs.glsl"
in vec2 texcoord;
in vec4 glcolor;
flat in float material;
/* RENDERTARGETS:0 */
layout(location = 0) out vec4 Color;
void main() {
    #ifdef COLORED_SHADOWS
        Color = glcolor;
        #if WATER_TEXTURE_MODE == 2
            Color *= vec4(0.7);
        #else
            Color *= texture(gtexture, texcoord);
        #endif

        if(Color.a < 0.1) discard;

        Color.rgb = to_linear(Color.rgb);
        // Color.rgb = mix(vec3(1), Color.rgb, Color.a);

        // Prevents accidentally sampling the solid's color
        if(Color.a > 0.9) Color.rgb = vec3(0);
    #else
        if(texture(gtexture, texcoord).a < 0.1) discard;
    #endif
}
