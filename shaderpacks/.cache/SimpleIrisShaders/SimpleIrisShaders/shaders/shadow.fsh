/*
    shadow.fsh
    ---------------------------------------------------------------
    Pipeline stage: SHADOW (depth-only geometry pass)
    Writes: depth only. gl_FragDepth is written implicitly by the
    fixed-function depth test - we don't even need a color output,
    which is why this shader is essentially empty. Keeping it this
    minimal is deliberate: any extra work here is paid for by every
    shadow-casting fragment in the scene, every frame.
    ---------------------------------------------------------------
*/
#version 330 compatibility

void main() {
    // No color output needed - shadow pass only writes depth.
}
