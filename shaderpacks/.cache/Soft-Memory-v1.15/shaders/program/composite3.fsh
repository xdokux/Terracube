/* RENDERTARGETS: 0 */

#include "/lib/all_the_libs.glsl"


varying vec2 texcoord;

const float weights[5] = float[5](0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216);

void main() {
    vec2 texelSize = 1.0 / vec2(viewWidth, viewHeight);
    float centerDepth = linearize_depth(texture2D(depthtex1, texcoord).r);
    
    vec3 verticalBlur = texture2D(colortex11, texcoord).rgb * weights[0];
   
    
    // The Vertical Blur Loop
    for(int i = 1; i < 5; i++) {
        vec2 offset = vec2(0.0, texelSize.y * float(i) * 3.0); 
        
        // --- Top Sample ---
        float sampleDepthT = linearize_depth(texture2D(depthtex1, texcoord + offset).r);
        float occlusionFactorT = 1.0 - smoothstep(0.0, 0.1, sampleDepthT - centerDepth);
        vec3 colorT = texture2D(colortex11, texcoord + offset).rgb;
        verticalBlur += colorT * weights[i] * occlusionFactorT;

        // --- Bottom Sample ---
        float sampleDepthB = linearize_depth(texture2D(depthtex1, texcoord - offset).r);
        float occlusionFactorB = 1.0 - smoothstep(0.0, 0.1, sampleDepthB - centerDepth);
        vec3 colorB = texture2D(colortex11, texcoord - offset).rgb;
        verticalBlur += colorB * weights[i] * occlusionFactorB;
    }
    
    vec3 sceneColor = texture2D(colortex0, texcoord).rgb;
    
    // Add the smooth light directly over the scene
    // By ADDING the blur instead of mixing, it behaves like a light bloom.
    // The 0.8 multiplier controls the intensity of the glow.
    vec3 finalColor = sceneColor + verticalBlur * 0.8;
    
    gl_FragData[0] = vec4(finalColor, 1.0);
}