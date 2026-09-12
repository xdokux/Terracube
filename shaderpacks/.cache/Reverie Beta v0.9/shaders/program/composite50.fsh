#include "/lib/all_the_libs.glsl"

in vec2 texcoord;

/* RENDERTARGETS:0 */
layout(location = 0) out vec4 Color;


void main() {

    #if AA_MODE == 1
    ivec2 Coords = ivec2(gl_FragCoord.xy);
    float L = texelFetchOffset(image0Sampler, Coords, 0, ivec2(0)).b;
    float R = texelFetchOffset(image0Sampler, Coords, 0, ivec2(1, 0)).a;
    float U = texelFetchOffset(image0Sampler, Coords, 0, ivec2(0)).r;
    float D = texelFetchOffset(image0Sampler, Coords, 0, ivec2(0, 1)).g;

    float Sum = L + U + R + D;
    if(Sum > 0.01) {
        bool h = max(L, R) > max(D, U);
        vec4 Offsets = h ? vec4(-L, 0, R, 0) : vec4(0, -U, 0, D);
        vec2 BlendFactor = h ? vec2(L, R) : vec2(U, D);
        BlendFactor /= dot(BlendFactor, vec2(1));

        //Offsets -= 0.5;

        vec3 FinalColor = vec3(0);
        FinalColor += pow(textureLod(colortex0, texcoord + Offsets.zw * resolutionInv, 0).rgb, vec3(2.2)) * BlendFactor.y;
        FinalColor += pow(textureLod(colortex0, texcoord + Offsets.xy * resolutionInv, 0).rgb, vec3(2.2)) * BlendFactor.x;

        Color.rgb = FinalColor;
        //Color.rgb += vec3(D);
    }
    else {
    #endif
        Color = textureLod(colortex0, texcoord, 0);
    #if AA_MODE == 1
        Color.rgb = pow(Color.rgb, vec3(2.2));
    }
    #endif
}
