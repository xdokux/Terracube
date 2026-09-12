#include "/lib/all_the_libs.glsl"

in vec2 texcoord;

/* RENDERTARGETS:0 */
layout(location = 0) out vec4 Color;

vec3 chromatic_aberration(vec2 texcoord) {
    vec2 Offset = (vec2(0.5) - texcoord) * CA_STRENGTH * 0.01;
    vec3 Color;
    Color.r = textureLod(colortex0, texcoord - Offset, 0).r;
    Color.g = textureLod(colortex0, texcoord, 0).g;
    Color.b = textureLod(colortex0, texcoord + Offset, 0).b;
    return Color;
}

void main() {
    #ifdef CHROMATIC_ABERRATION
        Color = vec4(chromatic_aberration(texcoord), 1);
    #else
        Color = texture(colortex0, texcoord);
    #endif

    Color.rgb *= 1 / (dataBuf.AvgLum * 9.6) * EXPOSURE_MULT;
    
    Color.rgb = apply_tonemap(Color.rgb);
}
