/* RENDERTARGETS: 0,10 */

#include "/lib/all_the_libs.glsl"
#include "/lib/distort.glsl"
#include "/global/sky.glsl"




#define TAU 6.28318530718
#define MAX_ITER 4
 
#define SEARCH_RADIUS 8
#define LIGHT_INTENSITY 5.0

uniform sampler2D gcolor;
uniform sampler2D lightmap;
uniform int heldBlockLightValue2;
uniform int heldItemId;
uniform int heldItemId2;

// Uniforms needed for slope bias


// --- Distant Horizons Uniforms ---
#ifdef DISTANT_HORIZONS
uniform sampler2D dhDepthTex0;
#endif

varying vec2 texcoord;

// --- Noise Helper for Soft Shadows ---
float InterleavedGradientNoise(vec2 position) {
    vec3 magic = vec3(0.06711056, 0.00583715, 52.9829189);
    return fract(magic.z * fract(dot(position, magic.xy)));
}

vec3 projectAndDivide(mat4 projectionMatrix, vec3 position){
  vec4 homPos = projectionMatrix * vec4(position, 1.0);
  return homPos.xyz / homPos.w;
}

float water_fog() {
    vec2 ScreenPos = gl_FragCoord.xy * resolutionInv;
    float TerrainDepth = texture2D(depthtex1, ScreenPos).x;
    TerrainDepth = linearize_depth(TerrainDepth);
    float ScreenDepth = linearize_depth(gl_FragCoord.z);
    // Make fog ramp up faster and thicker
    return smoothstep(2.0, 10.0, TerrainDepth - ScreenDepth) * WATER_FOG_STRENGTH * 2.0 * (1.0 + nightStrength);
}

float get_cloud_shadow(vec3 worldPos, vec3 sunDir) {
    if (sunDir.y < 0.05) return 1.0;
 
    float totalWorldTime = float(worldDay) * 24000.0 + float(worldTime);
    
    // --- Unified Wind & Warp (Fix for Pulsing/Desync) ---
    // This creates a stable, diagonal wind direction and a smooth, time-based turbulence effect.
    vec3 wind = vec3(totalWorldTime * 0.0035, 0.0, totalWorldTime * 0.0035);
    
    // --- Weather and Dynamic Density (Synced with sky.glsl) ---
    vec2 weatherCoords = fract(vec2(totalWorldTime * 0.00000095 * DYNAMIC_COVERAGE_MULT, totalWorldTime * 0.00000093 * DYNAMIC_COVERAGE_MULT));
    float weatherNoise = texture2D(noisetex, weatherCoords).r; 
    float dynamicCoverageOffset = (weatherNoise - CLEAR_PERCENTAGE) * WEATHER_VARIANCE;
    float finalOffset = mix(dynamicCoverageOffset, 0.9, wetness * 0.5);
    float rainOffset = wetness * 0.15;
 
    vec2 noiseCoords = fract(vec2(totalWorldTime * 0.000004 * DYNAMIC_DENSITY_MULT, totalWorldTime * 0.000003 * DYNAMIC_DENSITY_MULT));
    float densNoiseVal = texture2D(noisetex, noiseCoords).r; 
    float dynamicDensity = (densNoiseVal - 0.5) * DYNAMIC_DENSITY_RANGE * 2.0; 
    
    // We need to calculate myNight for the density multiplier to match the sky
    vec3 realSunPos = normalize(mat3(gbufferModelViewInverse) * sunPosition);
    float sunElev = realSunPos.y;
    float myNight = 1.0 - smoothstep(-0.15, 0.0, sunElev);
    float densityMultiplier = mix(dynamicDensity + (myNight * 8.0), 60.0, rainStrength);
 
    // --- Raymarch Setup ---
    float cloudBottom = CLOUD_LOWER;
    float cloudTop = CLOUD_UPPER * UPPER_CLOUD_MULTIPLIER;
    float layerThickness = cloudTop - cloudBottom;
    
    float distToClouds = (cloudBottom - worldPos.y) / max(sunDir.y, 0.01);
    vec3 startPos = worldPos + (sunDir * distToClouds);
    vec3 stepVector = (sunDir * (layerThickness / max(sunDir.y, 0.01))) / 4.0; // Using 4 steps for performance
    vec3 currentPos = startPos;
 
    float totalDensity = 0.0;
    float stepLength = length(stepVector);
 
    for (int i = 0; i < 4; i++) {
        // --- 1. THE ISLAND MAKER (from sky.glsl) ---
        vec3 coveragePos = vec3(currentPos.x, 150.0, currentPos.z) * 0.003 + wind; 
        float coverage = fbm_cheap(coveragePos) + finalOffset;        
        coverage = smoothstep(0.15 - rainOffset, 0.75 - rainOffset, coverage);

        if (coverage <= 0.01) {
            currentPos += stepVector;
            continue; 
        }

        // --- 2. THE 3D NOISE (from sky.glsl) ---
        float heightGradient = (currentPos.y - cloudBottom) / layerThickness;

        // Replace the pulsing wrapOffset with a stable, time-based noise lookup for turbulence.
        float warp_time = totalWorldTime * 0.002;
        vec3 warp = vec3(fbm_cheap(vec3(warp_time, 0.0, 0.0)), fbm_cheap(vec3(0.0, warp_time, 0.0)), fbm_cheap(vec3(0.0, 0.0, warp_time))) * 25.0;

        vec3 basePos = (currentPos + warp) * vec3(CLOUD_SCALE_X, CLOUD_SCALE_Y, CLOUD_SCALE_Z) + wind;
        float baseNoise = fbm_volumetric(basePos);

        float density = baseNoise * 2.0;
        density -= (1.0 - coverage) * 1.5; 
        density -= heightGradient * 0.4; 
        density *= smoothstep(0.0, 0.1, heightGradient);
        density = smoothstep(0.0, 0.3, density);

        density *= densityMultiplier;

        if (density > 0.0) {
            // Accumulate density based on the main renderer's formula
            totalDensity += density * stepLength * 0.005;
        }

        currentPos += stepVector;
    }
 
    return exp(-totalDensity);
}



//Core logic from David Hoskins, converted to a helper, you can find the original shader here : https://www.shadertoy.com/view/MdlXz8 
float get_caustic_sample(vec2 p, float t) {
    vec2 i = p;
    float c = 1.0;
    float inten = 0.0065;

    for (int n = 0; n < MAX_ITER; n++) {
        float t_layer = t * (1.0 - (3.0 / float(n + 1)));
        i = p + vec2(cos(t_layer - i.x) + sin(t_layer + i.y), 
                     sin(t_layer - i.y) + cos(t_layer + i.x));
        c += 1.0 / length(vec2(p.x / (sin(i.x + t_layer) / inten), 
                               p.y / (cos(i.y + t_layer) / inten)));
    }
    c /= float(MAX_ITER);
    return pow(abs(1.15 - pow(c, 1.2)), 10.0);
}

vec3 get_nostalgic_caustics_3d(vec3 worldPos) {

    vec2 p = mod(worldPos.xz * 1.2, TAU) - 150.0;
    float t = frameTimeCounter * 0.5 + 23.0;

    // Multiply by 9.5 for the bright spots
    vec3 caustics = vec3(get_caustic_sample(p,t)) * 9.5; 

    // THE FIX: Remove the solid waterColor addition!
    // Just return the raw light pattern, clamped so it doesn't break math
    return clamp(caustics, 0.0, 1.5); 

}

float get_nostalgic_caustics(vec3 worldPos) {
    vec2 p = mod(worldPos.xz, 1000.0) * 1.5; 
    float t = frameTimeCounter * 0.4;

    p.x += sin(p.y * 1.2 + t) * 0.5;
    p.y += sin(p.x * 1.2 + t) * 0.5;

    // Standard Caustic Layer
    float grid1 = sin(p.x * 2.5 + t) + sin(p.y * 2.5 - t);
    float grid2 = sin(p.x * 5.0 - t) + sin(p.y * 5.0 + t);
    float baseCaustics = 1.0 - abs((grid1 + grid2 * 0.2) * 0.4);
    baseCaustics = pow(max(0.0, baseCaustics), 4.0);

    // --- HOTSPOT LAYER ---
    float sparkleGrid = sin(p.x * 6.0 + t * 2.0) * sin(p.y * 6.0 - t * 1.5);
    float hotspots = pow(max(0.0, sparkleGrid), 16.0) * 2.5; 

    return baseCaustics + (hotspots * baseCaustics);
}

// --- UTILS ---

float get_eclipse_factor() {
    // 1. Recreate the exact same positions you used in the skybox
    vec3 baseJupPos = vec3(1500.0, 800.0, 0.0); 
    vec3 jupiterPos = rotateAxis(baseJupPos, vec3(0.0, 1.0, 0.0), frameTimeCounter * ORBIT_SPEED);
    vec3 sunPos = vec3(0.0, 1300.0, 2500.0); 

    // 2. Get their directions from the center of the world (camera origin)
    vec3 dirSun = normalize(sunPos);
    vec3 dirJup = normalize(jupiterPos);

    // 3. Calculate their apparent sizes in the sky (Radius / Distance)
    float sunAngularSize = 300.0 / length(sunPos);      // Approx 0.106
    float jupAngularSize = 800.0 / length(jupiterPos);  // Approx 0.403
    
    // The maximum distance between their centers before they start touching
    float touchDist = sunAngularSize + jupAngularSize;

    // 4. Check the actual distance between them on the sky dome
    float currentDist = distance(dirSun, dirJup);

    // 5. Output an eclipse factor: 0.0 (normal day) -> 1.0 (total eclipse)
    // We map the distance so that when they touch, it starts dimming, 
    // and when Jupiter mostly covers the Sun, it hits 1.0.
    float eclipseAmount = smoothstep(touchDist, touchDist * 0.3, currentDist);
    
    return eclipseAmount;
}

float check_is_underwater(vec2 texcoord) {
    float depthAll = texture2D(depthtex0, texcoord).r;
    float depthSolid = texture2D(depthtex1, texcoord).r;
    if (depthSolid >= 1.0) {
       return 0.0;
    }
    if (depthAll < depthSolid - 0.0001) return 1.0;
    if (isEyeInWater == 1 && depthAll > depthSolid - 0.0001) return 1.0;
    return 0.0;

}
vec3 GetShadowColorSoft(vec3 shadowCoord, float NdotL) {
    if (clamp(shadowCoord, 0.0, 1.0) != shadowCoord) return vec3(1.0);

    // 1. Robust Bias
    float baseBias = SHADOW_BIAS / SHADOW_MAP_RESOLUTION;
    float bias = baseBias * tan(acos(NdotL)); 
    bias = clamp(bias, baseBias, baseBias * 8.0);

    // 2. Controlled Softness
    float shadowMapDepth = texture2D(shadowtex1, shadowCoord.xy).r;
    float distToCaster = max(shadowCoord.z - shadowMapDepth, 0.0);
    
    // If shadows are too pixelated, reduce the 400.0 to 200.0
    float spread = (distToCaster * 400.0 + 1.0) / SHADOW_MAP_RESOLUTION;
    spread = clamp(spread, 0.5 * SHADOW_MAP_RESOLUTION, 20.0 / SHADOW_MAP_RESOLUTION);

    // 3. 32-Tap Golden Spiral
    // We use a high-frequency noise to break up the banding
    float noise = InterleavedGradientNoise(gl_FragCoord.xy);
    float angle = noise * 6.2831853;
    mat2 rot = mat2(cos(angle), -sin(angle), sin(angle), cos(angle));

    vec3 shadowAccum = vec3(0.0);
    const int SAMPLES = SOFT_SHADOWS_STEPS; // Optimized middle ground

    for(int i = 0; i < SAMPLES; i++) {
        // Fermat's Spiral for perfect distribution
        float r = sqrt(float(i + 0.5) / float(SAMPLES));
        float theta = float(i) * 2.3999632; // Golden Angle
        vec2 offset = rot * vec2(cos(theta), sin(theta)) * r * spread;
        
        vec2 sampleCoord = shadowCoord.xy + offset;
        float dAll = texture2D(shadowtex0, sampleCoord).r;
        float dOpaque = texture2D(shadowtex1, sampleCoord).r;
        
        float currentZ = shadowCoord.z - bias;

        if (currentZ < dAll) {
            shadowAccum += 1.0;
        } else if (currentZ < dOpaque) {
            shadowAccum += texture2D(shadowcolor0, sampleCoord).rgb;
        }
    }

    return shadowAccum / float(SAMPLES);
}

vec3 GetShadowColorSimple(vec3 shadowCoord, float NdotL) {
    // 1. No loops, no noise, no trig.
    // 2. Single bias
    float bias = 0.0007; 
    
    float depthOpaque = texture2D(shadowtex1, shadowCoord.xy).r;
    if (shadowCoord.z - bias < depthOpaque) return vec3(1.0);
    
    // Fallback to check for transparents (water/glass)
    float depthAll = texture2D(shadowtex0, shadowCoord.xy).r;
    if (shadowCoord.z - bias < depthAll) return texture2D(shadowcolor0, shadowCoord.xy).rgb;

    return vec3(0.0);
}

vec3 GetShadowColor(vec3 shadowCoord, float NdotL) {

    if (shadowCoord.x < 0.0 || shadowCoord.x > 1.0 ||

        shadowCoord.y < 0.0 || shadowCoord.y > 1.0 ||

        shadowCoord.z < 0.0 || shadowCoord.z > 1.0) {

        return vec3(1.0);

    }

   

    // 1. Calculate the base bias from your distort.glsl library

    float baseBias = SHADOW_BIAS/SHADOW_MAP_RESOLUTION;

   

    // 2. Gentle slope bias to fix the "rake" stripes on the ground

    float slope = sqrt(1.0 - NdotL * NdotL) / max(NdotL, 0.001);

    float slopeBias = clamp(slope, 0.0, 3.0);

    float finalBias = baseBias * (1.0 + slopeBias * 1.5);

   

    // 3. The Nostalgic Haze Setup

    float blurRadius = 2.5 / SHADOW_MAP_RESOLUTION;

   

    float noise = InterleavedGradientNoise(gl_FragCoord.xy);

    float angle = noise * 6.2831853;

    mat2 rotationMatrix = mat2(cos(angle), -sin(angle), sin(angle), cos(angle));



    // A fast, 4-tap cross pattern rotated by the noise

    vec2 offsets[4] = vec2[4](

        vec2( 1.0,  1.0),

        vec2(-1.0, -1.0),

        vec2(-1.0,  1.0),

        vec2( 1.0, -1.0)

    );



    vec3 shadowTotal = vec3(0.0);

   

    for(int i = 0; i < 4; i++) {

        vec2 offset = rotationMatrix * offsets[i] * blurRadius;

        vec2 sampleCoord = shadowCoord.xy + offset;

       

        float depthAll = texture2D(shadowtex0, sampleCoord).r;

        float depthOpaque = texture2D(shadowtex1, sampleCoord).r;

       

        if (shadowCoord.z - finalBias < depthAll) {

            shadowTotal += vec3(1.0); // Sun hits it fully

        }

        else if (shadowCoord.z - finalBias < depthOpaque) {

            // Sun is blocked by translucent block (glass/water)

            shadowTotal += texture2D(shadowcolor0, sampleCoord).rgb;

        }

        else {

            shadowTotal += vec3(0.0); // Blocked by solid block

        }

    }

   

    return shadowTotal / 4.0;

}

void main() {
    float depth = texture2D(depthtex1, texcoord).r;
    float depthAll = texture2D(depthtex0, texcoord).r;


    
     
    bool isDH = false;
    #ifdef DISTANT_HORIZONS
    float depthDH = texture2D(dhDepthTex1, texcoord).r;
    if (depth >= 1.0 && depthDH < 1.0) {
        depth = depthDH;
        isDH = true;
    }
    #endif

   vec2 uv = texcoord;


    vec3 distanceNDC = vec3(texcoord.xy, depth) * 2.0 - 1.0;
    vec3 distanceView;
    #ifdef DISTANT_HORIZONS
    if (isDH) {
        distanceView = projectAndDivide(dhProjectionInverse, distanceNDC);
    } else 
    #endif
    {
        distanceView = projectAndDivide(gbufferProjectionInverse, distanceNDC);
    }
    float truePixelDistance = length(distanceView);
  

    
    
    vec3 transColor = texture2D(colortex0, uv).rgb;
    bool isWater = texture(colortex12, uv).r == 1.0; // Using colortex12 as a mask for water blocks

    float isUnderwater = check_is_underwater(uv);

    // Compute world coordinates before distortion to prevent noise sliding
    vec3 undistortedPlayerPos = (gbufferModelViewInverse * vec4(distanceView, 1.0)).xyz;
    vec3 undistortedWorldPos = undistortedPlayerPos + cameraPosition;

    #ifdef HEATSHIMMER

    // 1. EARLY OUT OPTIMIZATION
    // If the pixel is closer than 30 blocks away, skip all the heavy math
    // and texture sampling entirely.
    if (truePixelDistance < SHIMMER_MIN_DISTANCE || depth >= 1.0 ) {
        vec3 Color = texture2D(colortex0, uv).rgb;
        // Output your color and return early here based on your shader structure
    } else if(isEyeInWater == 0) { // Only apply shimmer if not underwater

        
        float heatDistort = smoothstep(SHIMMER_MIN_DISTANCE, SHIMMER_MAX_DISTANCE, truePixelDistance); 
        
        float shimmerStrength = SHIMMER_STRENGHT * heatDistort * (dayStrength + sunsetStrength) * (1.0- rainStrength); // Max offset of 0.5% of the screen, only at far distances and during the day

       
        // Use world position to pin the noise pattern to the environment
        vec2 noiseUV = (undistortedWorldPos.xz + undistortedWorldPos.y) * 0.05 + vec2(0.0, frameTimeCounter * 10.0);

        // 4. Sample the noise and center it
        float noiseX = texture(noisetex, noiseUV).x - 0.5;
        float noiseY = texture(noisetex, noiseUV).y - 0.5;

        // 5. Apply the offset
        uv.x += noiseX * shimmerStrength;
        uv.y += noiseY * shimmerStrength;
    }

    #endif
    #ifdef WATER_REFRACTION
       
    if(isEyeInWater == 1 || (isUnderwater > 0.5 && isWater)) {
        // Use world position to pin the noise pattern to the environment
        vec2 noiseUV = (undistortedWorldPos.xz + undistortedWorldPos.y) * 0.05 + vec2(0.0, frameTimeCounter * UNDERWATER_DISTORTION_SPEED);
        noiseUV *= UNDERWATER_DISTORTION_SCALE; // Subtle distortion based on water color
        float noiseX = texture(noisetex, noiseUV).x - 0.5;
        float noiseY = texture(noisetex, noiseUV).y - 0.5;
        uv.x += noiseX * 0.02;
        uv.y += noiseY * 0.02;
    }
    #endif
    //convert the uv to worldpos to prevent sliding with the camera movement
    
    vec3 Color = texture2D(colortex0, uv).rgb;
   
    



    
    vec3 NDCPos = vec3(uv.xy, depth) * 2.0 - 1.0;
    vec3 viewPos;

  #ifdef DISTANT_HORIZONS
    if (isDH) {
       
        viewPos = projectAndDivide(dhProjectionInverse, NDCPos);
    } else 
    #endif
    {

        viewPos = projectAndDivide(gbufferProjectionInverse, NDCPos);
    }

    vec3 feetPlayerPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
    vec3 shadowViewPos = (shadowModelView * vec4(feetPlayerPos, 1.0)).xyz;
    vec4 shadowClipPos = shadowProjection * vec4(shadowViewPos, 1.0);
    shadowClipPos.z -= 0.001; // bias
    shadowClipPos.xyz = distortShadowClipPos(shadowClipPos.xyz); // distortion
    vec3 shadowNDCPos = shadowClipPos.xyz / shadowClipPos.w;
    vec3 shadowCoords = shadowNDCPos * 0.5 + 0.5;
 

    // --- Calculate NdotL for the Slope Bias ---
    vec3 viewNormal = texture2D(colortex9, uv).rgb * 2.0 - 1.0;
    vec3 viewLightDir = normalize(shadowLightPosition);


    #ifdef DIMENSION_END
        vec3 starPos = vec3(0, 300.0, 1500.0); 
        viewLightDir = normalize(mat3(gbufferModelView) * normalize(starPos));
    #endif
    float NdotL = clamp(dot(viewNormal, viewLightDir), 0.0, 1.0);

    // --- Sun Elevation Calculation ---
    // This is used for dynamic color mixing based on the sun's actual position in the sky.
    vec3 realSunPos = normalize(mat3(gbufferModelViewInverse) * sunPosition);
    float sunElev = realSunPos.y;
    float myDay = smoothstep(0.1, 0.3, sunElev);
    float myNight = 1.0 - smoothstep(-0.15, 0.0, sunElev);
    float goldenHour = 1.0 - clamp(myDay + myNight, 0.0, 1.0);
    float mySunrise = goldenHour * step(0.0, realSunPos.x);
    float mySunset  = goldenHour * step(realSunPos.x, 0.0);

   
        
    // Updated to pass NdotL so it compiles!
    float isSunlit = GetShadowColor(shadowCoords, NdotL).r; 

   

    vec3 absoluteWorldPos = feetPlayerPos + cameraPosition; 

    float fogFade = 1.0; 
    bool isValidCausticSurface = true;
    if (depth < 1.0) {
        vec2 lmCoord = texture2D(lightmap, uv).rg;
        float blockLight = lmCoord.x;

        vec3 shadowFloor = vec3((blockLight) * (1.0 + rainStrength * 10.0)); 
        
        vec3 incomingLight;

        #ifdef SOFT_SHADOWS
        incomingLight = GetShadowColorSoft(shadowCoords, NdotL);
        #elif defined FAST_SHADOWS
        incomingLight = GetShadowColorSimple(shadowCoords, NdotL); 
        #else
        incomingLight = GetShadowColor(shadowCoords, NdotL);
        #endif

      
        // 2. Get the sun direction in world space
        vec3 sunDirWorld = normalize(mat3(gbufferModelViewInverse) * shadowLightPosition);
        
        // 3. Calculate the shadow cast by the clouds
        float cloudShadow = get_cloud_shadow(absoluteWorldPos, sunDirWorld);
        
       
        
        // --- 2. CALCULATE WATER DEPTH JUST ONCE ---
        if (isUnderwater > 0.5 && (isWater || isEyeInWater == 1)) {
            
            float floorDepth = texture2D(depthtex1, uv).r;
            float surfaceDepth = texture2D(depthtex0, uv).r;
            
            vec4 cPos = vec4(uv * 2.0 - 1.0, floorDepth * 2.0 - 1.0, 1.0);
            vec4 vPos = gbufferProjectionInverse * cPos;
            if (abs(vPos.w) > 0.00001) vPos /= vPos.w; 
            
            vec4 cPosSurf = vec4(uv * 2.0 - 1.0, surfaceDepth * 2.0 - 1.0, 1.0);
            vec4 vPosSurf = gbufferProjectionInverse * cPosSurf;
            if (abs(vPosSurf.w) > 0.00001) vPosSurf /= vPosSurf.w;

            float waterDepth = distance(vPos.xyz, vPosSurf.xyz);
            if (isEyeInWater == 1) {
                waterDepth = length(vPos.xyz); 
            }

 
            fogFade = exp(-waterDepth * 0.55); 

            vec4 floorPos = gbufferModelViewInverse * vPos; 
            
   
            absoluteWorldPos = floorPos.xyz + cameraPosition;

            if(isEyeInWater == 1) {
               if (absoluteWorldPos.y > cameraPosition.y + 0.8) {
            isValidCausticSurface = false;
                }
            }

        }
        incomingLight *= fogFade;
        // 4. Darken the incoming shadow map light!
        #if defined(VOLUMETRIC_CLOUDS) && defined(CLOUD_SHADOW) 
        incomingLight *= cloudShadow;
        #endif

        float nightShadowFactor = 1.2;
        float shadowPower = mix(1.0, nightShadowFactor, myNight);
        vec3 finalShadow = max(incomingLight, shadowFloor);
        finalShadow = mix(vec3(1.0), finalShadow, shadowPower); 

      

        // --- Elevation-based Sun Color ---
        vec3 daySunColor = to_linear(vec3(1.0, 0.92, 0.82)) * 1.75; // Bright white sunlight
        vec3 sunsetSunColor = to_linear(vec3(1.58, 0.7, 0.5));   // Hot orange/pink sunset
        vec3 sunriseSunColor = to_linear(vec3(1.34, 0.7, 0.5));  // Peachy sunrise
        float rise_set_mix_sun = mySunrise / max(goldenHour, 1e-6);
        vec3 goldenHourSunColor = mix(sunsetSunColor, sunriseSunColor, rise_set_mix_sun);
        vec3 SUN_COLOR = mix(daySunColor, goldenHourSunColor, goldenHour);
        
        // Darken during rain/storms
        SUN_COLOR *= (1.0 - rainStrength * 0.8);
        
        // Increased multiplier for brighter sunlight
        SUN_COLOR *= SUN_COLOR_MULT;
        


        #ifdef DIMENSION_END
            SUN_COLOR = vec3(1.0) * SUN_COLOR_MULT_END;
        #endif
        
        const vec3 MOON_COLOR = to_linear(vec3(0.820, 0.761, 0.647))* 0.5; 
        vec3 currentLightColor = mix(SUN_COLOR, MOON_COLOR, myNight);
        float timeWeight = 1.2 - myNight; // Use elevation-based day factor

        #ifdef GODRAYS
            vec3 finalSunlight = currentLightColor * finalShadow;
        #else
            vec3 finalSunlight = currentLightColor * finalShadow * timeWeight;
        #endif

         #ifdef DIMENSION_END
            float eclipse = get_eclipse_factor();
            finalSunlight *= mix(1.0,0.05,eclipse);
        #endif 
        

        // --- Elevation-based Shadow Color ---
        vec3 dayShadow = to_linear(vec3(0.5, 0.5, 0.58));
        vec3 sunriseShadow = to_linear(vec3(0.1, 0.15, 0.2)); // Purplish tint for sunrise
        vec3 sunsetShadow = to_linear(vec3(0.2, 0.3, 0.3));   // Reddish tint for sunset

        #ifdef DIMENSION_END
            dayShadow = to_linear(vec3(0.1, 0.02, 0.15)); // Deep Nostalgic Purple for the End
            sunriseShadow = dayShadow;
            sunsetShadow = dayShadow;
        #endif
        vec3 nightLight = to_linear(vec3(0.01, 0.02, 0.05));

        float rise_set_mix_shadow = mySunrise / max(goldenHour, 1e-6);
        vec3 goldenHourShadow = mix(sunsetShadow, sunriseShadow, rise_set_mix_shadow);
        vec3 dayTimeShadow = mix(dayShadow, goldenHourShadow, goldenHour);

        vec3 ambientColor = mix(nightLight, dayTimeShadow, timeWeight);

        Color *= (ambientColor + finalSunlight);
        
        float gray = dot(Color, vec3(0.299, 0.587, 0.114));
        Color = mix(vec3(gray), Color, 1.15); 
        
        //ßColor *= 0.65; // Increased overall brightness slightly
        //Color *= vec3(1.05, 1.0, 0.95);
        // Photographic exposure curve prevents pure white blowouts while keeping things bright
        Color = 1.0 - exp(-Color * 1.1); // Further softened the exposure curve to make it even brighter

        Color = clamp(Color, 0.0, 1.0); // Ensure no color values exceed 1.0
        

        #ifdef SPECULAR
        //skip hand
        if(depth >= 0.56)   {
            // 1. Reconstruct vectors needed for specular
            vec3 viewDir = normalize(-viewPos); // viewPos is already calculated in your code
            vec3 lightDir = normalize(shadowLightPosition);
            vec3 reflectDir = reflect(-lightDir, viewNormal);

            // 2. Grab the smoothness/f0 data you saved in terrain.fsh
            vec4 specData = texture2D(colortex8, uv);
            float smoothness = specData.r;
            float f0 = specData.g;
            bool isMetal = f0 > 0.5; // Or however you define metalness

            // 3. Calculate the Specular Strength
            float NdotH = max(0.0, dot(reflectDir, viewDir));
            float specularStrength = pow(NdotH, 10.0 + (100.0 * smoothness)) * smoothness;

            // 4. THE FIX: Mask it by the shadow (incomingLight)
            // Use the shadow variable you calculated earlier in the file
            specularStrength *= incomingLight.r; 

            // 5. Calculate the final color using your original formula
            vec3 specularCol = (isMetal ? Color : vec3(1.0)) * specularStrength * f0 * 4.0;

            // 6. Add it to the final scene color
            #ifdef DIMENSION_END
                Color += specularCol * currentLightColor * timeWeight * 0.06;
            #else
                Color += specularCol * currentLightColor * timeWeight;
            #endif
        }

        #endif
    }
	#if defined(VOXELIZE) && !defined(FAST_SHADOWS)
    vec3 worldNormal = normalize(mat3(gbufferModelViewInverse) * viewNormal);

  

    // 1. Get the exact continuous position
    vec3 exactPos = feetPlayerPos + fract(cameraPosition) + vec3(32.0) + (worldNormal * 0.5);
    
    // 2. Calculate the Bayer Jitter
    const float bayer[16] = float[](
        0.0, 0.5, 0.125, 0.625,
        0.75, 0.25, 0.875, 0.375,
        0.1875, 0.6875, 0.0625, 0.5625,
        0.9375, 0.4375, 0.8125, 0.3125
    );
    
    int bX = (int(gl_FragCoord.x) % 4) + (int(gl_FragCoord.y) % 4) * 4;
    int bY = (int(gl_FragCoord.x + 1.0) % 4) + (int(gl_FragCoord.y + 2.0) % 4) * 4;
    int bZ = (int(gl_FragCoord.x + 2.0) % 4) + (int(gl_FragCoord.y + 1.0) % 4) * 4;

    vec3 jitter = vec3(bayer[bX], bayer[bY], bayer[bZ]) - 0.5;
    
    // Boost the blur radius! 0.65 forces it to sample neighboring columns
    jitter *= 0.65; 

    // 3. THE DOUBLE TAP: Read once forward, once backward, and average them!
    vec3 samplePos1 = exactPos - vec3(0.5) + jitter;
    vec3 samplePos2 = exactPos - vec3(0.5) - jitter; // Opposite direction

    float linearDepthSolid = linearize_depth(depth);
    float linearDepthAll = linearize_depth(depthAll);


    vec3 light1 = getTrilinearLight(samplePos1,isUnderwater,linearDepthAll,linearDepthSolid,isWater);
    vec3 light2 = getTrilinearLight(samplePos2,isUnderwater,linearDepthAll,linearDepthSolid,isWater);
    
    vec3 voxelLight = (light1 + light2) * 0.5;

    // --- HANDHELD LIGHTING INTEGRATION ---
    #ifdef HANDHELD_LIGHTS
    int heldLightValue = max(heldBlockLightValue, heldBlockLightValue2);
    if (heldLightValue > 0 && isEyeInWater == 0) {
        float distToPlayer = length(feetPlayerPos);
        float lightRadius = float(heldLightValue) * 1.2; // Slightly larger for a smoother fade
        if (distToPlayer < lightRadius) {
            float attenuation = clamp(1.0 - (distToPlayer / lightRadius), 0.0, 1.0);
            
            #ifdef HANDHELD_FALLOFF_CURVE
            attenuation *= attenuation; // Apply a quadratic falloff for softer edges
            #endif
            
            vec3 handheldColor = vec3(1.0, 0.65, 0.3); // Default Warm torch light
            
            // Determine which hand is holding the brighter light to select the correct ID
            int itemId = heldBlockLightValue >= heldBlockLightValue2 ? heldItemId : heldItemId2;
            
            if (itemId == 100) {
                handheldColor = vec3(0.2, 0.6, 1.0); // Soul light (Blue)
            } else if (itemId == 102) {
                handheldColor = vec3(1.0, 0.2, 0.2); // Redstone (Red)
            } else if (itemId == 104) {
                handheldColor = vec3(0.9, 0.8, 1.0); // End Rod (Slightly purplish white)
            }
            
            voxelLight += handheldColor * attenuation * 0.2;
        }
    }
    #endif

    // 4. The Corner Shaver (Smoothstep)
    voxelLight.r = smoothstep(0.001, 0.9, voxelLight.r);
    voxelLight.g = smoothstep(0.001, 0.9, voxelLight.g);
    voxelLight.b = smoothstep(0.001, 0.9, voxelLight.b);

    vec3 baseAlbedo = texture2D(colortex7, uv).rgb;

    Color += baseAlbedo * voxelLight * 2.0; // Blend the voxel light with the base albedo for a more natural effect 



    // Apply the light to the scene!
    // We now add the voxel light directly to the main color buffer.
    // The tonemapping curve prevents it from blowing out the image.
    vec3 tonemappedVoxelLight = voxelLight / (voxelLight + vec3(1.0));
    Color += tonemappedVoxelLight;
    tonemappedVoxelLight = clamp(tonemappedVoxelLight, 0.0, 1.0); // Ensure values are within [0, 1] for the bloom buffer


    gl_FragData[1] = vec4(tonemappedVoxelLight, 1.0); // Still write to the bloom buffer for the glow pass
	#endif

 #ifdef WATER_CAUSTICS
        // --- CAUSTIC LOGIC ---
    

        if (isUnderwater > 0.5 && isValidCausticSurface && isSunlit > 0.1 && (isWater || isEyeInWater == 1)) {
            
        
            #ifdef REALISTC_CAUSTICS
            float rPattern = get_nostalgic_caustics_3d(absoluteWorldPos + 0.08).r;
            float gPattern = get_nostalgic_caustics_3d(absoluteWorldPos).g;
            float bPattern = get_nostalgic_caustics_3d(absoluteWorldPos - 0.08).b;
            #else
            float rPattern = get_nostalgic_caustics(absoluteWorldPos + 0.04);
            float gPattern = get_nostalgic_caustics(absoluteWorldPos);
            float bPattern = get_nostalgic_caustics(absoluteWorldPos - 0.04);
            #endif            
            vec3 causticColor;
            causticColor.r = rPattern * 1.1; 
            causticColor.g = gPattern;
            causticColor.b = bPattern * 1.2; 

            vec3 sunTint = vec3(1.0, 0.9, 0.7); 
            vec3 finalCaustic = causticColor * sunTint;

            float intensity = (dayStrength + 0.001) * CAUSTICS_STRENGTH * 2.5 * (1.0-rainStrength);
            vec3 blendedCaustic = (Color.rgb * finalCaustic * 4.5) + (finalCaustic * 0.15);

            Color.rgb += blendedCaustic * isSunlit * intensity * fogFade;
            Color.rgb = clamp(Color.rgb, 0.0, 1.4);

            if (gPattern > 0.8) {
                Color.rgb += vec3(0.003, 0.02, 0.04) * gPattern * isSunlit;
            }
        }
    #endif

    

        if(isEyeInWater == 1) {
           
            float fogAmount = water_fog();
    

            Color = mix(Color, vec3(0.02, 0.4, 0.78), fogAmount) / (1.0 + nightStrength * 6.0);

    #ifdef GODRAYS
    vec3 PlayerPos = mat3(gbufferModelViewInverse) * viewPos;
    float maxDist = min(length(PlayerPos), 64.0); 
    vec3 rayDir = normalize(PlayerPos);

    const int steps = FOG_QUALITY; 
    float stepSize = maxDist / float(steps);

    float frameOffset = mod(frameTimeCounter * 100.0, 100.0);
    float jitter = getIGN(gl_FragCoord.xy + frameOffset); 

    vec3 currentPos = cameraPosition + rayDir * (stepSize * jitter);
    float volumetricAccum = 0.0; 

  
    vec3 sunDirWorld = normalize(mat3(gbufferModelViewInverse) * shadowLightPosition);
    float VoL = max(dot(rayDir, sunDirWorld), 0.0);
    

    float phase = pow(VoL, 4.0) * 2.5 + 0.4; 


    for(int i = 0; i < steps; i++) {
        vec3 playerRelativePos = currentPos - cameraPosition;
        vec3 shadowViewPos = mat3(shadowModelView) * playerRelativePos + shadowModelView[3].xyz;
        vec4 shadowClipPos = shadowProjection * vec4(shadowViewPos, 1.0);
        
        vec3 shadowPos = shadowClipPos.xyz / shadowClipPos.w;
        shadowPos = distortShadowClipPos(shadowPos);
        shadowPos = shadowPos * 0.5 + 0.5; 
        
        float shadow = 1.0; 
        
        if (clamp(shadowPos, 0.0, 1.0) == shadowPos) {
            float shadowMapDepth = texture2D(shadowtex1, shadowPos.xy).r;
            if (shadowMapDepth < shadowPos.z - 0.0005) { 
                shadow = 0.0; 
            }
        }
        
     
        float depthBeneathSurface = max(63.5 - currentPos.y, 0.0);
        
       
        float waterDecay = exp(-depthBeneathSurface * 0.15); 
        
     
        volumetricAccum += shadow * waterDecay; 
        
        currentPos += rayDir * stepSize;
    }

   
    float godrayStrength = (volumetricAccum / float(steps)) * 0.6; 
    vec3 godrayColor = vec3(0.15, 0.7, 0.95) / (1.0 + nightStrength * 3.0); 
    vec3 finalGodrays = godrayColor * godrayStrength * phase * (dayStrength + sunriseStrength + sunsetStrength);
    
   
    Color += finalGodrays;
    #endif
    }

    gl_FragData[0] = vec4(Color, 1.0);
}