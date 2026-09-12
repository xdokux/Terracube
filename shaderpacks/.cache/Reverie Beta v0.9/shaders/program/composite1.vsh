#include "/lib/all_the_libs.glsl"

flat out vec3 LightColorDirect;
out vec2 texcoord;
void main() {
    gl_Position = ftransform();
    gl_Position = gl_Position * 0.5 + 0.5;
    gl_Position.xy *= CLOUD_TEX_SIZE * resolutionInv;
    gl_Position = gl_Position * 2 - 1;
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    LightColorDirect = get_shadowlight_color();
}
