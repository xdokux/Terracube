#version 120
#define GBUFFER_FSH
#define TERRAIN
#include "/lib/settings.glsl"
#include "/lib/gbuffer.glsl"
void main() { gbufferFragment(0.1); }
