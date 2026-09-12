/* RENDERTARGETS: 11 */

#include "/lib/all_the_libs.glsl"   

varying vec2 texcoord;

// Gaussian Bell Curve weights
const float weights[5] = float[5](0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216);

void main() {
    vec2 texelSize = 1.0 / vec2(viewWidth, viewHeight);

    // Get the linearized depth of the current (center) pixel.
    float centerDepth = linearize_depth(texture2D(depthtex1, texcoord).r);

    // --- Voxel Light Threshold ---
    // Only blur pixels that are brighter than a certain threshold.
    // This creates a "bloom" effect from light sources, not just a general smudge.
    vec3 sourceColor = texture2D(colortex10, texcoord).rgb;
    float brightness = get_luminance(sourceColor);
    vec3 thresholdedColor = sourceColor * smoothstep(0.4, 0.8, brightness); // You can tweak 0.4 and 0.8
    
    // Start with the center pixel
    vec3 blurResult = thresholdedColor * weights[0];
    
    // The Horizontal Blur Loop
    for(int i = 1; i < 5; i++) {
        // Multiply by 3.0 to spread the light out wider!
        vec2 offset = vec2(texelSize.x * float(i) * 3.0, 0.0); 
        
        // --- Right Sample ---
        float sampleDepthR = linearize_depth(texture2D(depthtex1, texcoord + offset).r);
        // If the sample is much farther away, it's occluded. Reduce its contribution.
        float occlusionFactorR = 1.0 - smoothstep(0.0, 0.1, sampleDepthR - centerDepth);
        vec3 colorR = texture2D(colortex10, texcoord + offset).rgb;
        blurResult += colorR * weights[i] * smoothstep(0.4, 0.8, get_luminance(colorR)) * occlusionFactorR;

        // --- Left Sample ---
        float sampleDepthL = linearize_depth(texture2D(depthtex1, texcoord - offset).r);
        // If the sample is much farther away, it's occluded. Reduce its contribution.
        float occlusionFactorL = 1.0 - smoothstep(0.0, 0.1, sampleDepthL - centerDepth);
        vec3 colorL = texture2D(colortex10, texcoord - offset).rgb;
        blurResult += colorL * weights[i] * smoothstep(0.4, 0.8, get_luminance(colorL)) * occlusionFactorL;
    }
    
    // Write the result to colortex11 (mapped to Index 0 by the RENDERTARGETS at the top)
    gl_FragData[0] = vec4(blurResult, 1.0);
    
   
}