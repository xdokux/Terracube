#include "/lib/all_the_libs.glsl"

in vec4 glcolor;
in vec2 texcoord;

/* RENDERTARGETS:5 */
layout(location = 0) out vec4 Albedo;

void main() {
    vec4 Color = glcolor * texture(gtexture, texcoord);
    if(Color.a < 0.1) discard;
    float L = get_luminance(Color.rgb);
    Albedo = vec4(0, L, 0, 0);
}
