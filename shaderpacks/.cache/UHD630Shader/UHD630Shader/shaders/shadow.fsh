#version 120

varying vec2 texcoord;

uniform sampler2D texture;

void main() {
    // Alpha-test so leaves/foliage/glass don't cast solid black shadow blobs.
    vec4 tex = texture2D(texture, texcoord);
    if (tex.a < 0.1) discard;

    gl_FragColor = vec4(1.0);
}
