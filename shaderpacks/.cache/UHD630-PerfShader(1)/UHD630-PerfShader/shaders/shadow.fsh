#version 120

uniform sampler2D tex;

varying vec2 texcoord;
varying vec4 vColor;

void main() {
    vec4 color = texture2D(tex, texcoord) * vColor;
    // Alpha-test so leaves/glass/foliage don't cast solid black shadows
    if (color.a < 0.1) discard;

    gl_FragColor = color;
}
