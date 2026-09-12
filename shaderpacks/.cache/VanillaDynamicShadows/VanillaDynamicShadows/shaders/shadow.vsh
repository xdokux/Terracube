#version 330 compatibility
// Plain, undistorted shadow map render. The earlier pack in this
// series used a distortion warp for a pseudo-cascade look, but that
// warp's effective texel density changes continuously as the player
// moves - a subtle extra source of frame-to-frame instability that
// works against this pack's explicit "no jittery shadows" goal.
// Simple and stable wins here.
void main() {
    gl_Position = ftransform();
}
