#include "/lib/all_the_libs.glsl"
varying vec2 texcoord;
#include "/global/post/taa.glsl"

/* DRAWBUFFERS:01 */

vec3 motion_blur(vec3 Color, vec2 PrevCoord, vec2 CurrentCoord) {
    vec2 Velocity = PrevCoord - CurrentCoord;
    vec2 Offset = Velocity / 4.0 * MOTION_BLUR_STRENGTH;
    Offset *= 0.01666 / frameTime;
    vec3 Blur = Color;
    float Noise = bayer8(gl_FragCoord.xy);
    CurrentCoord += Offset * Noise;
    for (int i = 1; i < 4; i++) {
        Blur += texture2D(colortex0, CurrentCoord).rgb;
        CurrentCoord += Offset;
    }
    return Blur / 4.0;
}

void main() {
    vec4 Color = texture2D(colortex0, texcoord);

    #if TAA_MODE != 0 || defined MOTION_BLUR
    bool IsDH;
    float Depth = get_depth_solid(texcoord, IsDH);
    vec2 PrevCoord = toPrevScreenPos(texcoord, Depth, IsDH);
    #endif

    #ifdef MOTION_BLUR
    if (Depth >= 0.56) {
        Color.rgb = motion_blur(Color.rgb, PrevCoord, texcoord);
    }
    #endif

    #if TAA_MODE != 0
    if (Depth >= 0.56) {
        Color.rgb = TAA(Color.rgb, vec3(texcoord, Depth), PrevCoord, IsDH);
    }
    #endif

    Color.rgb *= EXPOSURE;
    Color.rgb = apply_tonemap(Color.rgb);

    #if TONEMAP_OPERATOR != 3
    #ifdef FAST_GAMMA
    Color.rgb = sqrt(Color.rgb);
    #else
    Color.rgb = pow(Color.rgb, vec3(1.0 / 2.2));
    #endif
    #endif

    #ifdef IMAGE_SHARPENING
    vec3 center = Color.rgb;
    vec3 off = (
        texture2D(colortex0, texcoord + vec2(resolutionInv.x, 0.0)).rgb +
        texture2D(colortex0, texcoord - vec2(resolutionInv.x, 0.0)).rgb +
        texture2D(colortex0, texcoord + vec2(0.0, resolutionInv.y)).rgb +
        texture2D(colortex0, texcoord - vec2(0.0, resolutionInv.y)).rgb
    ) * 0.25;
    off = apply_tonemap(off * EXPOSURE);
    #ifndef FAST_GAMMA
    off = pow(off, vec3(1.0 / 2.2));
    #else
    off = sqrt(off);
    #endif
    Color.rgb = center + (center - off) * SHARPENING;
    Color.rgb = clamp(Color.rgb, 0.0, 1.0);
    #endif

    #ifdef FILM_GRAIN
    float grain = fract(sin(dot(gl_FragCoord.xy + frameTimeCounter, vec2(12.9898, 78.233))) * 43758.5453);
    grain = (grain - 0.5) * FILM_GRAIN_STRENGTH;
    Color.rgb += grain;
    #endif

    gl_FragData[0] = vec4(Color.rgb, 1.0);
    gl_FragData[1] = vec4(Color.rgb, 1.0);
}
