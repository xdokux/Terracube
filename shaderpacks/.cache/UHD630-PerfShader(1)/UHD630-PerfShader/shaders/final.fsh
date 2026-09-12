#version 120

uniform sampler2D colortex0;

varying vec2 texcoord;

void main() {
    vec3 color = texture2D(colortex0, texcoord).rgb;

    // BUGFIX (v1 -> v2): v1 applied Reinhard tonemapping AND a pow(1/2.2)
    // gamma curve here. That's wrong for this pack: every color reaching
    // this point (vanilla block/entity textures, lightmap, our godray
    // additions) is already in gamma/display space - nothing upstream
    // works in linear HDR. Re-tonemapping and re-gamma-correcting
    // already-correct colors is "double gamma correction," a classic
    // shader bug, and it's exactly what produces a washed-out, low
    // contrast, artificially bright/desaturated image.
    // Fix: just clamp (safety net against any additive overflow from
    // the godray pass) and output directly.
    color = clamp(color, 0.0, 1.0);

    gl_FragColor = vec4(color, 1.0);
}
