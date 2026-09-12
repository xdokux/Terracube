#include "/lib/all_the_libs.glsl"

#ifndef DOF_HIGHLIGHT_BOOST
#define DOF_HIGHLIGHT_BOOST 400.0
#endif

varying vec2 texcoord;

/* DRAWBUFFERS:6 */
// 6 = colortex6 (Write Focus Data)

// Configs for Focus Speed
#ifndef DOF_FOCUS_ADJUSTMENT_SPEED
#define DOF_FOCUS_ADJUSTMENT_SPEED 2.0 
#endif

// --- CoC Function ---

float calc_CoC(float Depth, float DepthCenter) {

    float validDepthCenter = max(DepthCenter, 0.0001);

    float focalLength = validDepthCenter / (validDepthCenter + 1.0);

    float CoC = abs(DOF_APERTURE_SIZE * (focalLength * (Depth - validDepthCenter)) /

              (Depth * (validDepthCenter - focalLength)));

    return CoC;

}



// --- Vogel Disk ---

const vec2 vogel_disk[32] = vec2[](

    vec2(0.120644, 0.015554), vec2(-0.164000, 0.161802),

    vec2(0.020080, -0.262883), vec2(0.196866, 0.278013),

    vec2(-0.373623, -0.049763), vec2(0.345446, -0.206961),

    vec2(-0.121357, 0.450796), vec2(-0.227491, -0.414079),

    vec2(0.479759, 0.192352), vec2(-0.507996, 0.223450),

    vec2(0.238432, -0.503270), vec2(0.175058, 0.587555),

    vec2(-0.545112, -0.297825), vec2(0.630013, -0.123909),

    vec2(-0.391501, 0.566229), vec2(-0.093795, -0.674645),

    vec2(0.544716, 0.478312), vec2(-0.743234, 0.046109),

    vec2(0.534599, -0.520777), vec2(-0.040413, 0.795345),

    vec2(-0.517173, -0.598972), vec2(0.808003, 0.124856),

    vec2(-0.692666, 0.494463), vec2(0.183730, -0.820506),

    vec2(0.430677, 0.774745), vec2(-0.854804, -0.255761),

    vec2(0.821746, -0.366125), vec2(-0.362243, 0.870709),

    vec2(-0.323763, -0.872479), vec2(0.845552, 0.462242),

    vec2(-0.948390, 0.264398), vec2(0.532240, -0.818975)

);

vec3 blur_dof( vec2 texcoord, float CoC) {
    vec3 Sum = vec3(0.0);
    float TotalWeight = 0.0;
    float blurFactor = CoC * gbufferProjection[1][1] / 1.37;
    vec2 Radius = resolutionInv * blurFactor;

    for(int i = 0; i < DOF_BLUR_QUALITY; i++) {
        vec2 Offset = vogel_disk[i] * Radius;
        float lod = max(0.0, log2(blurFactor * 0.5));

        // Sample Color
        vec3 SampleColor = texture2DLod(colortex0, texcoord + Offset, lod).rgb;

        // Sample Bloom for Bokeh Weight
        vec3 BloomSample = texture2DLod(colortex1, texcoord + Offset, lod).rgb;
        float Weight = 1.0 + (length(BloomSample) * DOF_HIGHLIGHT_BOOST);

        Sum += SampleColor * Weight;
        TotalWeight += Weight;
    }
    return Sum / TotalWeight;
}


void main() {
    // 1. PASS-THROUGH COLOR (Crucial!)
    // We must keep the main image alive for the final stage
    gl_FragData[0] = texture2D(colortex0, texcoord);

    // 2. FOCUS LOGIC
    bool IsDH;
    float DepthCenter;

    #ifdef DOF_MANUAL_FOCUS
        DepthCenter = 0.5; // Dummy, unused in manual mode usually
    #else
        // Get raw depth at center
        float CurrentCenterDepth = get_depth(vec2(0.5), IsDH);

        // Read history from Buffer 6 (Previous Frame)
        float OldDepth = texelFetch(colortex6, ivec2(0, 0), 0).r;

        // Safety for first frame
        if (OldDepth <= 0.0) OldDepth = CurrentCenterDepth;

        // Smooth it
        float BlendFactor = clamp(frameTime * DOF_FOCUS_ADJUSTMENT_SPEED, 0.0, 1.0);
        DepthCenter = mix(OldDepth, CurrentCenterDepth, BlendFactor);
    #endif


    

    // 3. WRITE DATA
    // We store the raw depth in the Red channel of Buffer 6
    gl_FragData[0] = vec4(DepthCenter, 0.0, 0.0, 1.0);
}