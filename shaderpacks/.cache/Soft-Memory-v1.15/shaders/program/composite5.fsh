#include "/lib/all_the_libs.glsl"
#include "/global/post/bloom.glsl"

varying vec2 texcoord;
varying vec2 PrevTilePos;



/* DRAWBUFFERS:1 */
vec3 getStarburst(sampler2D tex, vec2 uv, vec2 direction, float spreadDistance, vec2 texelSize) {
    vec3 resultColor = vec3(0.0);
    float totalWeight = 0.0;
    
    const int SAMPLES = 30; 
    
    // --- NOSTALGIA SETTINGS ---
    // Increase this for a more "broken camera" look
    float chromaticSpread = 10.5; 
    
    for (int i = -SAMPLES; i <= SAMPLES; i++) {
        float weight = exp(-abs(float(i)) * 0.005); 
        vec2 offset = direction * (float(i) / float(SAMPLES)) * spreadDistance * texelSize;

        // Split the channels by adding a tiny extra offset to Red and Blue
        // Red pulls slightly further away, Blue stays closer to center
        float r = texture2D(tex, uv + offset * (1.0 + 0.02 * chromaticSpread)).r * 1.05;
        float g = texture2D(tex, uv + offset).g;
        float b = texture2D(tex, uv + offset * (1.0 - 0.02 * chromaticSpread)).b * 0.95;
        
        vec3 sampleColor = vec3(r, g, b);
        
        // Crush and Clamp as per your original logic
        vec3 sharpColor = pow(max(sampleColor, vec3(0.0)), vec3(3.0)); 
        sharpColor = min(sharpColor, vec3(2.0));
        
        resultColor += sharpColor * weight;
        totalWeight += weight;
    }
    
    return resultColor / max(totalWeight, 0.0001);
}
void main() {
    vec3 softBloom = blur3x3(colortex1, PrevTilePos).xyz;
    vec2 texelSize = 1.0 / vec2(viewWidth, viewHeight);
    vec3 finalStarburst= vec3(0.0);
    #ifdef STAR_BURST_EFFECT

    // Get the camera's forward direction in world space to create a subtle, dynamic rotation.
    // This breaks the perfectly static screen-aligned look.
    vec3 viewDir = normalize(gbufferModelViewInverse[2].xyz);
    
    // Create a slight rotation based on the camera's horizontal angle.
    // The 0.1 multiplier keeps the effect subtle, preventing wild spinning.
    float angle = atan(viewDir.x, viewDir.z) * 0.1;
    mat2 rotation = mat2(cos(angle), -sin(angle), sin(angle), cos(angle));

    // Apply the rotation to the base streak directions.
    vec2 dir1 = rotation * vec2(1.0, 0.0); // Rotated horizontal streak

    vec3 streak1 = getStarburst(colortex1, PrevTilePos, dir1, STAR_BURST_SPREAD, texelSize);
    

    finalStarburst = streak1;
    #endif

    vec3 finalColor = softBloom + (finalStarburst * (1.0 + nightStrength * 2.5) * STAR_BURST_STRENGHT);
    finalColor = clamp(finalColor, 0.0, 1.2);
    gl_FragData[0].xyz = finalColor;
   
}