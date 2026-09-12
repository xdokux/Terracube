#include "/lib/all_the_libs.glsl"
#include "/global/lighting.vsh"

void main() {
    texcoord = gl_MultiTexCoord0.xy;
    glcolor  = gl_Color;

    init_generic();

    #if TAA_MODE >= 2
    gl_Position.xy += taaJitter * gl_Position.w;
    #endif
}
