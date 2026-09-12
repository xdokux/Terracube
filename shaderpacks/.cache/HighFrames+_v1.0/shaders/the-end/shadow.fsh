#version 330 compatibility

uniform sampler2D gtexture;

in float mask;
in vec2 texcoord;
in vec4 glcolor;

layout(location = 0) out vec4 color;

void main() {
    color = texture(gtexture, texcoord) * glcolor;
    if (color.a < 0.1) discard;
    if (abs(mask - 5.0) < 0.01) discard;
}