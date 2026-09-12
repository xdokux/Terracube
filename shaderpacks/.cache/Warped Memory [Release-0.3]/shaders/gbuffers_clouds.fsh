#version 330 compatibility

uniform sampler2D gtexture;
in vec2 texcoord;
in vec4 glcolor;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

void main() {
    vec4 tex = texture(gtexture, texcoord);

    if (tex.a < 0.1) discard;

    color = tex * glcolor;
}
