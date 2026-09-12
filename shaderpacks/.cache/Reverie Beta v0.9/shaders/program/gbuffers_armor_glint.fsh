#include "/lib/all_the_libs.glsl"

in vec2 texcoord;

/* RENDERTARGETS:10 */
layout(location = 0) out vec4 Color;

void main() {
	Color = texture(gtexture, texcoord);

    if (Color.a < 0.1) {
        discard;
        return;
    }

    Color.rgb = srgb_linear(Color.rgb);
}

