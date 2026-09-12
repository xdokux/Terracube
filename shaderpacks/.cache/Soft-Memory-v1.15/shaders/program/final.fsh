#include "/lib/all_the_libs.glsl"

varying vec2 texcoord;
uniform sampler2D shadowcolor1;


#include "/global/post/taa.glsl"
#include "/global/post/cas.glsl"
#include "/global/post/chromatic_aberration.glsl"
#include "/global/post/apply_warm_tint.glsl"

#ifndef DOF_HIGHLIGHT_BOOST
#define DOF_HIGHLIGHT_BOOST 400.0
#endif

vec3 film_grain(vec3 Color, vec2 Pos) {
    // 1. Stutter the time to simulate a ~15 FPS vintage camera / low-quality tape
    float stutterTime = floor(frameTimeCounter * 15.0);
    Pos.x += fract(stutterTime / 4.14159) * 234.0;
    Pos.y -= fract(stutterTime / 5.49382) * 567.0;
    
    // 2. Horizontally stretch the noise to mimic VHS/CRT scanline interference
    vec2 noiseUV = vec2(Pos.x * 0.4, Pos.y) / 255.0;
    vec3 noise = texture2D(noisetex, noiseUV).rgb - 0.5;

    #ifdef DYNAMIC_FILM_GRAIN
    
    // 3. Luminance masking & Low-Light Boosting
    float luma = dot(Color, vec3(0.299, 0.587, 0.114));
    float mask = 1.0 - smoothstep(0.6, 1.0, luma); // Keep grain out of highlights
    
    // Boost grain intensity in shadows and mid-tones to simulate sensor noise
    float lowLightBoost = 1.0 + (1.0 - smoothstep(0.0, 0.4, luma)) * 2.5;


    
    // Apply the noise with a safe fallback to prevent division by zero on strict GPUs
    Color += noise * clamp((FILM_GRAIN_STRENGTH/max(rainStrength, 0.0001)), 0.0025, FILM_GRAIN_STRENGTH) * mask * lowLightBoost;
    #else
    Color += noise * clamp((FILM_GRAIN_STRENGTH/max(rainStrength, 0.0001)), 0.0025, FILM_GRAIN_STRENGTH);
    #endif
    

    #ifdef FILM_GRAIN_PULSE
    float grainPulse = 0.85 + 0.15 * sin(frameTimeCounter * 0.6);
    return Color * grainPulse;
    #else
    return Color;
    #endif
}

vec3 dream_glow(vec3 color, vec2 uv) {
    vec3 blurred = vec3(0.0);
    float totalWeight = 0.0;
    
    // Simple 9-tap box blur for softness (efficient)
    // We spread it out a bit wide to make it look "hazy"
    float spread = 3.0; 
    
    for(float x = -1.0; x <= 1.0; x++) {
        for(float y = -1.0; y <= 1.0; y++) {
            vec2 offset = vec2(x, y) * spread / vec2(viewWidth, viewHeight);
            // We sample LOD 2.0 to get a pre-blurred, softer input
            blurred += texture2DLod(colortex0, uv + offset, 2.0).rgb;
            totalWeight += 1.0;
        }
    }
    blurred /= totalWeight;
    
    // "Screen" blending makes it look like light, not just a dull blur
   
    return max(color, mix(color, blurred, DREAMINESS_STRENGHT) * 1.2); 
}

vec3 apply_light_leak(vec3 Color, vec2 Pos) {
    // Slow moving, warm, reddish-orange glow on the edges
    float t = frameTimeCounter * 0.15;
    
    // Create soft, shifting blotches using sine waves to mimic organic light bleeding
    float wave1 = sin(Pos.x * 4.0 + t) * cos(Pos.y * 3.0 - t * 0.8) * 0.5 + 0.5;
    float wave2 = sin(Pos.y * 5.0 + t * 1.2) * cos(Pos.x * 2.5 + t * 0.5) * 0.5 + 0.5;
    float noise = (wave1 + wave2) * 0.5;
    
    // Mask mostly to the left/right edges, like cheap disposable cameras
    float edgeMask = smoothstep(0.2, 1.0, abs(Pos.x - 0.5) * 2.0);
    float flicker = 0.9 + 0.1 * sin(frameTimeCounter * 8.0);
    
    float intensity = noise * edgeMask * flicker * 0.25; 
    vec3 leakColor = vec3(1.0, 0.25, 0.05); // Warm reddish-orange film burn
    
    return Color + (leakColor * intensity);
}

vec3 apply_vignette(vec3 Color, vec2 Pos) {
    Pos = Pos - 0.5;
    Pos *= VIGNETTE_OPACITY;
    float Strength = len2(Pos);
    Strength = pow(Strength, 2 - VIGNETTE_FALLOFF);
    Color *= 1 - min(Strength, 1);
    return Color;
}

float randLine(float y, float t) {
    return fract(sin(dot(vec2(y, t), vec2(12.9898,78.233))) * 43758.5453);
}

float dropout(vec2 uv) {
    float t = frameTimeCounter * 0.5;
    return step(0.995, fract(sin(dot(vec2(floor(uv.y * 240.0), t), vec2(12.9898,78.233))) * 43758.5453));
}

float luma(vec3 c) {
    return dot(c, vec3(0.299, 0.587, 0.114));
}

vec3 colorBleed(vec2 uv) {
    vec3 c0 = texture2D(colortex0, uv).rgb;
    vec3 c1 = texture2D(colortex0, uv + vec2( 1.5 / viewWidth, 0)).rgb;
    vec3 c2 = texture2D(colortex0, uv + vec2(-1.5 / viewWidth, 0)).rgb;

    float y0 = luma(c0);
    vec3 chroma0 = c0 - y0;

    vec3 chroma = (c1 + c2) * 0.5 - y0;
    return vec3(y0) + chroma;
}


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
    float jitter = fract(sin(dot(texcoord * resolution, vec2(12.9898,78.233))) * 43758.5453);
    float blurFactor = CoC * gbufferProjection[1][1] / 1.37;
    blurFactor *= mix(0.92, 1.08, jitter);
    vec2 Radius = resolutionInv * blurFactor;

    for(int i = 0; i < DOF_BLUR_QUALITY; i++) {
        vec2 Offset = vogel_disk[i] * Radius;
        float lod = max(0.0, log2(blurFactor * 3.5));

        // Sample Color
        // Vintage Lens Effect: Scale the offsets per-channel to create chromatic aberration 
        // on the edges of the bokeh discs.
        vec3 SampleColor;
        SampleColor.r = texture2DLod(colortex0, texcoord + Offset * 1.05, lod).r;
        SampleColor.g = texture2DLod(colortex0, texcoord + Offset, lod).g;
        SampleColor.b = texture2DLod(colortex0, texcoord + Offset * 0.95, lod).b;

        // Sample Bloom for Bokeh Weight
        vec3 BloomSample = texture2DLod(colortex1, texcoord + Offset, lod).rgb;
        float Weight = 1.0 + (length(BloomSample) * DOF_HIGHLIGHT_BOOST);

        Sum += SampleColor * Weight;
        TotalWeight += Weight;
    }
    return Sum / TotalWeight;
}

// CAS

void main() {
    vec2 uv=texcoord;

    

    vec3 glowColor= texture2D(colortex1,texcoord).rgb;

     bool IsDH;
        float Depth = get_depth(texcoord, IsDH);
        float DepthL = ld_exact(Depth, IsDH);

    
    
    #ifdef LOW_RES
        uv = floor(uv * resolution * RES) / (resolution * RES);
    #endif

    #ifdef IMAGE_SHARPENING
    vec4 Color = vec4(CAS(colortex0), 1);
    #else
        #ifdef VHS_JITTER
        vec2 jitter = vec2(0.0);
        float j = sin(frameTimeCounter * 12.0) * 0.0001;
        jitter.x = j;
        uv += jitter;
        uv.x += sin(uv.y * 120.0 + frameTimeCounter * 6.0) * 0.0015;
        float tracking = smoothstep(0.9, 1.0, uv.y);
        uv.x += sin(uv.y * 80.0 + frameTimeCounter * 10.0) * 0.004 * tracking;
        #endif
       
         
    vec4 Color = texture2D(colortex0, uv);
    #endif

        #ifdef DOF
        float DepthCenter = texture2D(colortex6, vec2(0.5)).r;
        float DepthCenterL;
        #ifdef DOF_MANUAL_FOCUS
            DepthCenterL = DOF_FOCUS_DISTANCE;
        #else
            DepthCenterL = ld_exact(DepthCenter, IsDH);
        #endif

        float CoC = calc_CoC(DepthL, DepthCenterL);
        CoC = Depth < 0.56 ? min(10.0, CoC) : min(20.0, CoC);

        vec3 FinalColor = blur_dof(texcoord, CoC);
        
        // Now Color is the blurred image, ready to be graded below
        Color.rgb = mix(Color.rgb,FinalColor,1.4);
    #endif

    
    




    Color.rgb = clamp(apply_vibrance(Color.rgb, VIBRANCE-(rainStrength*2)),0.4,2.6);
    Color.rgb = clamp(apply_saturation(Color.rgb, SATURATION-(rainStrength*2)),0.4,2.6);
    Color.rgb = clamp(apply_contrast(Color.rgb, CONTRAST-(rainStrength/3)),0.1,4.0);

    vec3 MinBright = vec3(TONEMAP_MIN_R, TONEMAP_MIN_G, TONEMAP_MIN_B);
    Color.rgb = max(Color.rgb, MinBright);
    Color.rgb = mix(Color.rgb, vec3(0.08), 0.05);
    Color.rgb *= vec3(1.02, 1.00, 0.97);


  
    Color.rgb = mix(Color.rgb, colorBleed(uv), 0.6);
    #ifdef DREAMY_GLOW
    Color.rgb = dream_glow(Color.rgb, uv);
    #endif
    #ifdef ANAMORPHIC_EFFECT
    Color.rgb=anamorphicEffect(Color.rgb,uv); 
    #endif

    #ifdef FILM_GRAIN
    Color.rgb = film_grain(Color.rgb, gl_FragCoord.xy);
    #endif


    #ifdef LIGHT_LEAK
    Color.rgb = apply_light_leak(Color.rgb, texcoord);
    #endif
    

    
   // Color.rgb=applyWarmTint(Color.rgb,1);
    Color.rgb = apply_vignette(Color.rgb, texcoord);

    #ifdef VHS_DROPOUT

    float y = floor(uv.y * 240.0);
    float base = randLine(y * 0.25, floor(frameTimeCounter * 13.0));

    float d = step(1.0 - 0.001, base);

    if (d > 0.0) {
        Color.rgb *= 0.3;                  // darken
        Color.rgb += vec3(0.1, 0.1, 0.1);   // gray noise feel
    }

    #endif



    float glowStrenght =2.0;

   // Color.rgb +=(glowColor * glowStrenght);

    //Color.rgb *= vec3(1.03, 1.05, 1.00);


    Color.xyz += (bayer8(gl_FragCoord.xy) - 0.5) / 255;

   

    gl_FragData[0] = Color;

    
}
