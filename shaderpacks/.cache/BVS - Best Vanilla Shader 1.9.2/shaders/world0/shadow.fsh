#version 130

in vec2 TexCoords;
in vec4 Color;

uniform sampler2D texture;

void main() {
    gl_FragData[0] = texture2D(texture, TexCoords) * Color;
}