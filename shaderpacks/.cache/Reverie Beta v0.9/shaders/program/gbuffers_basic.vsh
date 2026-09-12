#include "/lib/all_the_libs.glsl"
#include "/generic/lighting/gbuffers.vsh"

flat out vec4 glcolor_flat;
void main() {
  init_generic();
  glcolor_flat = DataOut.glcolor;
}
