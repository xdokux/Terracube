#include "/lib/all_the_libs.glsl"
#include "/global/fog.glsl"
#include "/global/sky.glsl"
#include "/global/water.glsl"
#include "/global/post/godrays.glsl"
// Godrays

varying vec2 texcoord;

/* DRAWBUFFERS:0 */

void main() {
    vec4 Color = texture2D(colortex0, texcoord);
    bool IsDH;
    float Depth = get_depth(texcoord, IsDH);
    vec3 ScreenPos = vec3(texcoord, Depth);

    if (Depth >= 0.56) { // Skip JUST the hand
        #if defined DIMENSION_OVERWORLD && defined GODRAYS
        Color.rgb += godrays(ScreenPos, IsDH);
        #endif
    }

    gl_FragData[0] = Color;
}
