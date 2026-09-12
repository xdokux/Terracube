// shadow.fsh
// Depth-only. The GPU's own depth write is all shadowtex0/1 need; there's
// nothing to output. Left as a real (empty) main rather than omitting the
// file, since Iris expects a fragment stage to exist for the shadow program.

void main() {
}
