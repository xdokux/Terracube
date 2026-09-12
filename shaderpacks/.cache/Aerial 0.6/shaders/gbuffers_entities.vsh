#version 120
#define GBUFFER_VSH
#include "/lib/settings.glsl"
#include "/lib/gbuffer.glsl"
void main() { gbufferVertex(); }
