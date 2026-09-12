#version 120

uniform sampler2D texture;

varying vec2 texcoord;
varying vec4 vcolor;

void main() {
    gl_FragColor = texture2D(texture, texcoord) * vcolor;
}