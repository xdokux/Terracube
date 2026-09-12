/*
    shadow.vsh
    ---------------------------------------------------------------
    Pipeline stage: SHADOW (depth-only geometry pass)
    Reads: vanilla vertex attributes for every shadow-casting object
    Writes: shadowtex0 / shadowtex1 (depth only, no color targets)

    This is the pass that hits integrated GPUs hardest - it's a
    second full pass over most of the scene's geometry, so draw-call
    and vertex throughput matter here as much as fragment cost.
    Nothing fancy is done in this file on purpose.
    ---------------------------------------------------------------
*/
#version 330 compatibility

void main() {
    gl_Position = ftransform();
}
