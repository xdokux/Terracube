#include "/lib/all_the_libs.glsl"

in vec2 texcoord;
flat in vec3 LightColorDirect;

#include "/generic/clouds.glsl"
#include "/generic/sky.glsl"
#include "/generic/post/taa.glsl"

/* RENDERTARGETS:3 */
layout(location = 0) out vec4 CloudColor;

void main() {
    vec2 P = texcoord * 2 - 1;
    vec2 P2 = pow2(P);
    vec3 PlayerPosN;
    PlayerPosN.x = (2 * P.x);
    PlayerPosN.z = (2 * P.y);
    PlayerPosN.y = (1 - P2.x - P2.y);
    float Denom = 1 + P2.x + P2.y;
    PlayerPosN /= Denom;
    float Dither = bayer8(gl_FragCoord.xy);

    float _Void = 1e6;
    CloudColor.rgb = get_clouds(vec3(1000), PlayerPosN, 8, cameraPosition, false, gl_FragCoord.xy, 1, _Void).rgb;
    
    CloudColor.rgb += get_aurora(PlayerPosN, Dither);
}
