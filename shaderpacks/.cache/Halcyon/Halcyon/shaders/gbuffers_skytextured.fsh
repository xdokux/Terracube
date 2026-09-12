#version 120

uniform sampler2D texture;

varying vec2 texcoord;
varying vec4 vertexColor;

void main() {
    vec4 tex = texture2D(texture, texcoord);
    if (tex.a < 0.05) discard;

    // Pushed above 1.0 on purpose - composite1's bloom bright-pass picks this up
    gl_FragColor = vec4(tex.rgb * vertexColor.rgb * 2.2, tex.a * vertexColor.a);
}
