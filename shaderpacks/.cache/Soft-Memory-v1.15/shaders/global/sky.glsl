float fogify(float x, float w) {
    return w / (x * x + w);
}


float hash3D(vec3 p){
    p = fract(p * 0.3183099 + 0.1);
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float randomJitter(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float noise3D(vec3 x) {
    vec3 i = floor(x);
    vec3 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash3D(i + vec3(0,0,0)), hash3D(i + vec3(1,0,0)), f.x),
                   mix(hash3D(i + vec3(0,1,0)), hash3D(i + vec3(1,1,0)), f.x), f.y),
               mix(mix(hash3D(i + vec3(0,0,1)), hash3D(i + vec3(1,0,1)), f.x),
                   mix(hash3D(i + vec3(0,1,1)), hash3D(i + vec3(1,1,1)), f.x), f.y), f.z);
}


vec3 wrapOffset(float time){
    float freq = 0.02;
    float strength = 8.0;

    vec3 offset;
    offset.x = noise3D(vec3(time * 0.5, 12.4, 34.1) * freq);
    offset.y = noise3D(vec3(34.1, time * 0.5, 2.1) * freq); // Offset seeds
    offset.z = noise3D(vec3(5.2, 1.4, time * 0.5) * freq);

    return (offset * 2.0 - 1.0) * strength;
}

float fbm_volumetric(vec3 p) {
    float f = 0.0;
    float amp = 0.5;
    for(int i = 0; i < 4; i++) {
        f += amp * noise3D(p);
        p *= 2.02;
        amp *= 0.5;
    }
    return f;
}

// A cheaper FBM with fewer octaves for broad checks.
float fbm_cheap(vec3 p) {
    float f = 0.0;
    float amp = 0.5;
    // Only 2 octaves instead of 4
    for(int i = 0; i < 2; i++) {
        f += amp * noise3D(p);
        p *= 2.02;
        amp *= 0.5;
    }
    return f;
}

float get_altocumulus(vec3 worldRd, float time){
    float height = 8000.0;
    float t = height / max(worldRd.y, 0.01);
    if (worldRd.y < 0.02) return 0.0; // Fade at horizon

    vec2 uv = (worldRd.xz * t) * 0.0004; // Very small scale for high clouds
    uv += time * 0.02; // Slow high-altitude wind

    // 2. Mackerel Pattern (Cellular/Voronoi approximation using FBM)
    // Sample FBM but manipulate the result to create "gaps"
    float n = fbm_volumetric(vec3(uv.x, 0.0, uv.y) * 8.0);
    
    // Create the "patches" by using a lower frequency mask
    float mask = fbm_volumetric(vec3(uv.x, 0.0, uv.y) * 0.5);
    mask = smoothstep(0.4, 0.7, mask);

    // Shape the "cells": high contrast smoothstep creates the rounded puffs
    float clouds = smoothstep(0.35, 0.5, n);
    clouds *= mask;

    // Horizon fade to prevent sharp cutoff
    clouds *= smoothstep(0.02, 0.15, worldRd.y);

    return clouds;
}

vec3 get_nostalgic_volumetrics(vec3 viewDir, vec3 worldPos, vec3 sunDir, vec3 skyColor, vec3 sunGlare, float ReflectionDimmer, out float cloudTransmittance, bool isReflection, float reflectionPlaneY) {

    float horizonFade = smoothstep(0.0, 0.08, viewDir.y);

    float safeViewDirY = abs(viewDir.y) < 0.0001 ? (viewDir.y >= 0.0 ? 0.0001 : -0.0001) : viewDir.y;
    float distToLower = (CLOUD_LOWER - worldPos.y) / safeViewDirY;
    float distToUpper = (CLOUD_UPPER - worldPos.y) / safeViewDirY;

    vec3 startPos = worldPos + viewDir * max(0.0, distToLower);
    vec3 endPos = worldPos + viewDir * distToUpper;
    int STEPS = 2; // Base steps for raymarching
    if(!isReflection) {
        STEPS = VOLUMETRIC_CLOUDS_QUALITY;
    }else {
        int raw = int(floor(VOLUMETRIC_CLOUDS_QUALITY / 2)); // Keep reflections super cheap
        STEPS = max(16, raw);
    }

    vec3 stepDir = (endPos - startPos) / float(STEPS);

    float stepLength = length(stepDir);
    stepLength = min(stepLength, 50.0);

    vec3 p = startPos + stepDir * randomJitter(viewDir.xy * 1000.0);

    // --- CALCULATE TIME OF DAY FROM SUN VECTOR ---
    vec3 realSunPos = normalize(mat3(gbufferModelViewInverse) * sunPosition);
    float sunElev = realSunPos.y;
    float myDay = smoothstep(0.1, 0.3, sunElev);
    float myNight = 1.0 - smoothstep(-0.15, 0.0, sunElev);
    float goldenHour = 1.0 - clamp(myDay + myNight, 0.0, 1.0);
    float mySunrise = goldenHour * step(0.0, sunDir.x);
    float mySunset  = goldenHour * step(sunDir.x, 0.0);
    float dayFactor = 1.0 - myNight;

    // --- DYNAMIC SKY BACKDROP ---
    vec3 noonUpperSky = vec3(SKY_NOON_UPPER_R, SKY_NOON_UPPER_G, SKY_NOON_UPPER_B);
    vec3 noonLowerSky = vec3(SKY_NOON_LOWER_R, SKY_NOON_LOWER_G, SKY_NOON_LOWER_B);
    
    vec3 sunsetUpperSky = vec3(SKY_SUNSET_UPPER_R, SKY_SUNSET_UPPER_G, SKY_SUNSET_UPPER_B);
    vec3 sunsetLowerSky = vec3(SKY_SUNSET_LOWER_R, SKY_SUNSET_LOWER_G, SKY_SUNSET_LOWER_B);

    vec3 sunriseUpperSky = vec3(SKY_SUNRISE_UPPER_R, SKY_SUNRISE_UPPER_G, SKY_SUNRISE_UPPER_B); 
    vec3 sunriseLowerSky = vec3(SKY_SUNRISE_LOWER_R, SKY_SUNRISE_LOWER_G, SKY_SUNRISE_LOWER_B);

    vec3 nightUpperSky = vec3(SKY_NIGHT_UPPER_R, SKY_NIGHT_UPPER_G, SKY_NIGHT_UPPER_B);
    vec3 nightLowerSky = vec3(SKY_NIGHT_LOWER_R, SKY_NIGHT_LOWER_G, SKY_NIGHT_LOWER_B);

    // Mix the sky based on the sun's height (Linked to Sun Vector!)
    vec3 upperSky = (noonUpperSky * myDay) + (sunsetUpperSky * mySunset) + (sunriseUpperSky * mySunrise) + (nightUpperSky * myNight);
    vec3 lowerSky = (noonLowerSky * myDay) + (sunsetLowerSky * mySunset) + (sunriseLowerSky * mySunrise) + (nightLowerSky * myNight);

    float gradientMix = pow(clamp(1.0 - viewDir.y, 0.0, 1.0), 2.5);
    vec3 customSky = mix(upperSky, lowerSky, gradientMix);

    // --- TERMINATOR ZONE (Earth's Shadow & Belt of Venus) ---
    vec2 antiSunDirXZ = length(realSunPos.xz) > 0.0001 ? -normalize(realSunPos.xz) : vec2(1.0, 0.0);
    vec2 viewDirXZ = length(viewDir.xz) > 0.0001 ? normalize(viewDir.xz) : vec2(1.0, 0.0);
    float antiSunDot = max(dot(viewDirXZ, antiSunDirXZ), 0.0);
    
    float terminatorIntensity = pow(antiSunDot, 1.5) * goldenHour;
    float terminatorHeight = 0.05 - sunElev * 0.3; // Rises as the sun sets
    
    float earthShadowMask = 1.0 - smoothstep(terminatorHeight - 0.02, terminatorHeight + 0.05, viewDir.y);
    float venusBeltMask = smoothstep(terminatorHeight - 0.02, terminatorHeight + 0.05, viewDir.y) * 
                          (1.0 - smoothstep(terminatorHeight + 0.02, terminatorHeight + 0.15, viewDir.y));
                          
    vec3 earthShadowColor = vec3(0.02, 0.03, 0.08); // Dark blueish-purple
    vec3 venusBeltColor = vec3(0.85, 0.35, 0.45);   // Vibrant pink/magenta
    
    customSky = mix(customSky, earthShadowColor, earthShadowMask * terminatorIntensity * 0.8);
    customSky += venusBeltColor * venusBeltMask * terminatorIntensity * 0.5;

    

    // --- TWILIGHT ARCH (Sun's Glow below the horizon) ---
    vec2 sunDirXZ = length(realSunPos.xz) > 0.0001 ? normalize(realSunPos.xz) : vec2(1.0, 0.0);
    float sunHorizonDot = max(dot(viewDirXZ, sunDirXZ), 0.0);
    // Twilight peaks when sun is just below the horizon (-0.1 to 0.0)
    float twilightTime = smoothstep(-0.15, -0.02, sunElev) * (1.0 - smoothstep(-0.05, 0.05, sunElev));
    float twilightArch = pow(sunHorizonDot, 3.0) * (1.0 - smoothstep(-0.05, 0.15, viewDir.y));
    vec3 twilightColor = vec3(1.0, 0.35, 0.15); // Fiery orange/red twilight
    customSky += twilightColor * twilightArch * twilightTime * 1.2;

    skyColor = mix(skyColor, customSky, 0.75 * dayFactor);

    float horizon = smoothstep(-0.05, 0.15, viewDir.y);

    if(isReflection) {
        // Dim the horizon to 40% brightness while keeping the upper sky at 100%
        skyColor *= mix(0.4, 1.0, horizon);

   
        // Reflections are dimmer and more saturated
        skyColor *= 2.5;
        skyColor = mix(skyColor, vec3(0.2, 0.3, 0.5), 0.3); // Slightly more blue tint
    }

    float totalWorldTime = float(worldDay) * 24000.0 + float(worldTime);

   // --- DYNAMIC CLOUD COLORS ---
    vec3 noonShadow = vec3(CLOUD_NOON_SHADOW_R, CLOUD_NOON_SHADOW_G, CLOUD_NOON_SHADOW_B); 
    vec3 noonLight = vec3(CLOUD_NOON_LIGHT_R, CLOUD_NOON_LIGHT_G, CLOUD_NOON_LIGHT_B) + sunGlare * 0.3; 

    vec3 sunsetShadow = vec3(CLOUD_SUNSET_SHADOW_R, CLOUD_SUNSET_SHADOW_G, CLOUD_SUNSET_SHADOW_B); 
    vec3 sunsetLight = vec3(CLOUD_SUNSET_LIGHT_R, CLOUD_SUNSET_LIGHT_G, CLOUD_SUNSET_LIGHT_B) + sunGlare * 0.6; 

    vec3 sunriseShadow = vec3(CLOUD_SUNRISE_SHADOW_R, CLOUD_SUNRISE_SHADOW_G, CLOUD_SUNRISE_SHADOW_B); 
    vec3 sunriseLight = vec3(CLOUD_SUNRISE_LIGHT_R, CLOUD_SUNRISE_LIGHT_G, CLOUD_SUNRISE_LIGHT_B) + sunGlare * 0.4;

    vec3 nightShadow = vec3(CLOUD_NIGHT_SHADOW_R, CLOUD_NIGHT_SHADOW_G, CLOUD_NIGHT_SHADOW_B); 
    vec3 nightLight = vec3(CLOUD_NIGHT_LIGHT_R, CLOUD_NIGHT_LIGHT_G, CLOUD_NIGHT_LIGHT_B); 

    vec3 shadowBase = (noonShadow * myDay) + (sunsetShadow * mySunset) + (sunriseShadow * mySunrise) + (nightShadow * myNight);
    vec3 lightBase = (noonLight * myDay) + (sunsetLight * mySunset) + (sunriseLight * mySunrise) + (nightLight * myNight);
    
    // --- TWILIGHT CLOUD UNDERGLOW ---
    // Light up the clouds from below after the sun sets!
    float cloudUnderglow = max(dot(viewDir, normalize(vec3(sunDirXZ.x, 0.2, sunDirXZ.y))), 0.0);
    vec3 twilightCloudTint = twilightColor * pow(cloudUnderglow, 2.0) * twilightTime * 2.0;
    lightBase += twilightCloudTint;
    shadowBase = mix(shadowBase, twilightColor * 0.3, twilightTime * 0.5);

    vec3 scatteredLight = vec3(0.0);
    float transmittance = 1.0; 
    float VdotL = dot(viewDir, sunDir);
    vec3 wind = vec3(totalWorldTime * 0.002, 0.0, totalWorldTime * 0.005);

    // --- THE RAYMARCHING LOOP ---
    for (int i = 0; i < STEPS; i++) {
        if (transmittance < 0.01) break; 

        // --- PERFORMANCE OPTIMIZATION: EMPTY SPACE SKIPPING ---
        // Use a cheaper noise function to quickly check if we're likely in empty space.
        // This avoids running all the expensive logic below for every single step.
        vec3 cheapPos = p * vec3(CLOUD_SCALE_X, CLOUD_SCALE_Y, CLOUD_SCALE_Z) * 0.5 + wind * vec3(0.01, 0.0, 0.01);
        float cheapNoise = fbm_cheap(cheapPos);
        if (cheapNoise < 0.2) {
            p += stepDir;
            continue;
        }

        float CLOUD_THICKNESS = (CLOUD_UPPER * UPPER_CLOUD_MULTIPLIER) - CLOUD_LOWER;
        
        float heightGradient = (p.y - CLOUD_LOWER) / CLOUD_THICKNESS;

        // --- 1. THE ISLAND MAKER ---
        vec3 coveragePos = vec3(p.x, 150.0, p.z) * 0.003 + wind * vec3(0.005, 0.0, 0.005);
        float coverage = fbm_cheap(coveragePos); // OPTIMIZATION: Use cheaper FBM for coverage


        // Sample noise very slowly over the world's lifespan. 
        vec2 weatherCoords = vec2(totalWorldTime * 0.00000095 * DYNAMIC_COVERAGE_MULT, totalWorldTime * 0.00000093 * DYNAMIC_COVERAGE_MULT);

        weatherCoords = fract(weatherCoords);
        float weatherNoise = texture2D(noisetex, weatherCoords).r; 


        float dynamicCoverageOffset = (weatherNoise - CLEAR_PERCENTAGE) * WEATHER_VARIANCE;


        float finalOffset = mix(dynamicCoverageOffset, 0.9, wetness * 0.5);


        coverage += finalOffset;
        
 
        coverage = smoothstep(0.15, 0.75, coverage);
        float rainOffset = wetness * 0.15; 
        coverage = smoothstep(0.15 - rainOffset, 0.75 - rainOffset, coverage);

        if (coverage <= 0.01) {
            p += stepDir;
            continue; 
        }

        // --- 2. THE 3D NOISE ---
        vec3 warp = wrapOffset(totalWorldTime * 0.01);
        vec3 basePos = (p + warp) * vec3(CLOUD_SCALE_X, CLOUD_SCALE_Y, CLOUD_SCALE_Z) + wind;
        float baseNoise = fbm_volumetric(basePos);


        float density = baseNoise * 2.0;


        density -= (1.0 - coverage) * 1.5; 


        density -= heightGradient * 0.4; 


        density *= smoothstep(0.0, 0.1, heightGradient);


        density = smoothstep(0.0, 0.3, density);

        vec2 noiseCoords = vec2(totalWorldTime * 0.000004 * DYNAMIC_DENSITY_MULT, totalWorldTime * 0.000003 * DYNAMIC_DENSITY_MULT);

        float noiseVal = texture2D(noisetex, noiseCoords).r; 

        
        float dynamicDensity = (noiseVal - 0.5) * DYNAMIC_DENSITY_RANGE * 2.0; 

        float densityMultiplier = mix(dynamicDensity + (myNight * 8.0), 60.0, rainStrength);

    density *= densityMultiplier;

    if (density > 0.0) {
      float stepTransmittance = exp(-density * stepLength * 0.005); 
      float VdotL = dot(viewDir, sunDir);
      float dayFactor = 1.0 - myNight;

      // --- THE LIGHTING COMPOSITION (CRITICAL) ---

      // 1. Fake Multiple Scattering (Keeps the core bright, and adds internal glow)
      // Multiplies the light inside the cloud. Try 1.5 - 2.5 range.
      float internalScattering = 2.2;
      // --- THE BRIGHTNESS FIX ---

// 1. Lift the shadows! Mix your shadow base with the vibrant sky color 
// so the dark parts feel airy and blue/purple, not muddy gray.
vec3 liftedShadow = mix(shadowBase, skyColor, 0.6); // Increased mix for airier shadows
// NOSTALGIA: Enhanced for that vibrant summer feel: cyan-blue shadows at noon, lavender at sunset
vec3 nostalgiaTint = mix(vec3(0.05, 0.15, 0.30), vec3(0.20, 0.10, 0.25), mySunset + mySunrise);
liftedShadow += nostalgiaTint * dayFactor * (1.0 - rainStrength);

// 2. Smoother, softer transition into shadow using Beer's Law, 
// rather than a harsh clamp.
float shadowMix = 1.0 - exp(-density * stepLength * 0.012); // Slightly softer shadow falloff
vec3 currentLight = mix(lightBase, liftedShadow, shadowMix);

// 3. Fake Multiple Scattering (The "Glow" multiplier)
// NOSTALGIA: Increased the core glow and added a slight golden warmth
//currentLight *= 2.5; // Boosted core brightness for blinding summer clouds
currentLight += vec3(0.15, 0.08, 0.0) * max(VdotL, 0.0) * dayFactor; // Warmer sun bleed


// 4. Intense Rim Light (Silver/Golden lining)
// --- ENHANCED SILVER LINING ---
float rimLight = pow(max(VdotL, 0.0), 12.0) * exp(-density * 0.1); // Sharper, tighter rim
currentLight += vec3(1.0, 0.9, 0.8) * rimLight * 8.0 * dayFactor * (1.0 - rainStrength); // Brighter, whiter silver edge
// 3. Beer's Law Simulation (Dual Transmission)
      
      // Direct sun is blocked quickly (preserves the bright, sharp sun-facing edges)
      float directTransmission = exp(-density * stepLength * 0.02);
      
      // Ambient sky light is blocked very slowly (preserves the fluffy details in the dark spots)
      float ambientTransmission = exp(-density * stepLength * 0.003); 
      
      // Calculate direct light contribution
      float directIllum = directTransmission + (max(VdotL, 0.0) * 0.3 * dayFactor);
      
      // Calculate ambient light contribution 
      // The 0.25 is the absolute darkest "floor", and it smoothly gets brighter up to +0.35
      float ambientIllum = 0.25 + (0.35 * ambientTransmission);
      
      // Combine them without any harsh clamps!
      float illumination = directIllum + ambientIllum;
      
      currentLight = mix(currentLight, currentLight * illumination, dayFactor);

      // Accumulate light and transmittance...
      scatteredLight += transmittance * currentLight * (1.0 - stepTransmittance);
      transmittance *= stepTransmittance;
 }
        p += stepDir;
    }

    if (transmittance > 0.1) {
    float altocumulus = get_altocumulus(viewDir, totalWorldTime * 0.05); 
    
    if (altocumulus > 0.01) {
        // Lighting for the high layer
        float highVdotL = dot(viewDir, sunDir);
        
        vec3 highRim = lightBase * pow(max(highVdotL, 0.0), 8.0) * 6.0;
        vec3 highCloudCol = mix(shadowBase, lightBase, 0.8) + highRim;
        
        // Blend into the accumulated light based on remaining transmittance
        scatteredLight += transmittance * highCloudCol * altocumulus * 0.7;
        transmittance *= (1.0 - altocumulus * 0.6);
    }
}

    // Add horizon "Smog" dynamically (less smog at noon, thicker at sunset)
    // Summer heat haze makes the horizon brighter and more cyan
    float horizonMist = pow(1.0 - viewDir.y, 3.5); // Broader haze
    vec3 noonSmog = vec3(0.80, 0.92, 1.0); // Brighter, softer cyan for summer heat
    vec3 sunsetSmog = vec3(1.0, 0.55, 0.45);  // Vibrant peach/coral
    vec3 sunriseSmog = vec3(0.95, 0.65, 0.85); // Bubblegum pink
    
    vec3 smogColor = (noonSmog * myDay) + (sunsetSmog * mySunset) + (sunriseSmog * mySunrise);
    scatteredLight = mix(scatteredLight, smogColor * 0.5, horizonMist * (1.0 - myNight)); // Increased haze intensity

    // Final distance fade and tone map
    float distFade = exp(-distance(worldPos, p) * 0.0007);
    // --- ADD THIS TONEMAPPING LINE ---
    scatteredLight = 1.0 - exp(-scatteredLight * 2.2); 

    if (isReflection) {
        scatteredLight *= 2.0; // Massive boost for cloud reflections only
    }

    scatteredLight = mix(skyColor, scatteredLight, distFade);
    
    vec3 finalColor= mix(scatteredLight, skyColor, transmittance);

    cloudTransmittance = mix(1.0, transmittance, horizonFade); 
 
    // When rendering reflections, we don't want the final dimmer.
    return mix(skyColor, isReflection ? finalColor : finalColor * ReflectionDimmer, horizonFade);
}





// 2. UV Mapping (Equirectangular)
// Converts a 3D point on a sphere to 2D texture coordinates
vec2 sphereUV(vec3 p) {
   // Clamp p.y to prevent NaN errors at the very top/bottom pixels
    float px = (abs(p.x) < 0.00001 && abs(p.z) < 0.00001) ? 0.00001 : p.x;
    float u = 0.5 + atan(p.z, px) / 6.2831853; 
    float v = 0.5 + asin(clamp(p.y, -1.0, 1.0)) / 3.1415926;
    
    return vec2(u, v);
}



//A fallback to the new textured moon
vec3 simple_sun(float Dist) {

    Dist = Dist * 0.5 + 0.5;

    vec3 realSunPos = normalize(mat3(gbufferModelViewInverse) * sunPosition);
    float sunElev = realSunPos.y;
    float myDay = smoothstep(0.1, 0.3, sunElev);
    float myNight = 1.0 - smoothstep(-0.15, 0.0, sunElev);
    float goldenHour = 1.0 - clamp(myDay + myNight, 0.0, 1.0);

    const vec3 SUN_COLOR = vec3(5, 3.5, 0.8);

    const vec3 MOON_COLOR = vec3(1, 1.5, 2.5);

    float What = goldenHour;

    vec3 Color = SUN_COLOR * (1 - smoothstep(0., 0.0015, 1 - Dist)) * (myDay + What);

    Color += MOON_COLOR * (smoothstep(0.9995, 1., 1 - Dist)) * (myNight + What);

    Color *= 1 - rainStrength;

    return Color;

}

// Ray-Sphere Intersection (Reuse from Jupiter)
float intersectSphereMoon(vec3 ro, vec3 rd, vec3 so, float sr) {
    vec3 oc = ro - so;
    float b = dot(oc, rd);
    float c = dot(oc, oc) - sr * sr;
    float h = b * b - c;
    if (h < 0.0) return -1.0;
    return -b - sqrt(h);
}



vec3 round_sun(vec3 viewDir, vec3 sunDir,vec3 PlayerPosN) {
    vec3 finalColor = vec3(0.0);
    
    // --- PART 1: THE SUMMER NOSTALGIA SUN ---
float VdotL = max(dot(viewDir, sunDir), 0.0);
float distFromCenter = 1.0 - VdotL; 

// Using 'exp' creates a perfectly smooth, infinite falloff instead of harsh rings.
// Smaller multiplier = wider spread.
float core   = exp(-distFromCenter * 1000.0); // Default was 3500. Lower to ~1500 for a bigger white center
float corona = exp(-distFromCenter * 200.0);  // Default was 400. Lower to ~150 for a broad golden ring
float haze   = exp(-distFromCenter * 15.0);   // Default was 60. Lower to ~25 for a massive sky-bleed

// Adjusted colors to blend beautifully into the blue sky without turning purple
vec3 coreColor = vec3(10.0);  // Blinding warm center
vec3 coronaColor = vec3(9.0); // Intense golden middle
vec3 hazeColor = vec3(0.6, 0.55, 0.51);// Soft, warm atmospheric bleed
    
    // --- Fiery Orange Sunrise ---
    vec3 sunriseCoreColor = vec3(5.0, 2.5, 0.5); // Bright orange-yellow core
    vec3 sunriseCoronaColor = vec3(4.5, 1.5, 0.2); // Deep fiery orange corona
    vec3 sunriseHazeColor = vec3(0.7, 0.5, 0.4); // Warm pinkish haze
    
    // --- Fiery Orange Sunset ---
    vec3 sunsetCoreColor = vec3(5.0, 2.0, 0.0); // Intense orange-red core
    vec3 sunsetCoronaColor = vec3(4.8, 1.2, 0.1); // Saturated deep orange corona
vec3 sunsetHazeColor = vec3(0.8, 0.4, 0.3); // Reddish haze for sunset

    vec3 realSunPos = normalize(mat3(gbufferModelViewInverse) * sunPosition);
    float sunElev = realSunPos.y;
    float myDay = smoothstep(0.1, 0.3, sunElev);
    float myNight = 1.0 - smoothstep(-0.15, 0.0, sunElev);
    float goldenHour = 1.0 - clamp(myDay + myNight, 0.0, 1.0);
    float mySunrise = goldenHour * step(0.0, realSunPos.x);
    float mySunset  = goldenHour * step(realSunPos.x, 0.0);

    float rise_set_mix = mySunrise / max(goldenHour, 1e-6);
    vec3 goldenHourCoreColor = mix(sunsetCoreColor, sunriseCoreColor, rise_set_mix);
    vec3 goldenHourCoronaColor = mix(sunsetCoronaColor, sunriseCoronaColor, rise_set_mix);
    vec3 goldenHourHazeColor = mix(sunsetHazeColor, sunriseHazeColor, rise_set_mix);

    vec3 finalCoreColor = mix(coreColor, goldenHourCoreColor, goldenHour);
    vec3 finalCoronaColor = mix(coronaColor, goldenHourCoronaColor, goldenHour);
    vec3 finalHazeColor = mix(hazeColor, goldenHourHazeColor, goldenHour);


vec3 nostalgicSun = (core * finalCoreColor) + (corona * finalCoronaColor) + (haze * finalHazeColor);

float HorizonFade = smoothstep(0.0, 0.1, PlayerPosN.y);

// Draw the new sun
finalColor = nostalgicSun * HorizonFade;
    
    

    vec3 moonDir = -sunDir; 
    vec3 moonPos = moonDir * 100.0; 
    float moonRadius = 10.0; 

    float intersect = intersectSphereMoon(vec3(0.0), viewDir, moonPos, moonRadius);
if (intersect > 0.0) {
        vec3 hitPos = viewDir * intersect;
        vec3 normal = normalize(hitPos - moonPos);
        
        // Transform the normal to world space so the moon phase and texture don't rotate with the camera
        vec3 worldNormal = mat3(gbufferModelViewInverse) * normal;
        vec3 tiltedNormal = rotateAxis(worldNormal, vec3(0.0, 1.0, 0.0), radians(90.0)); // Base rotation to orient the texture
        tiltedNormal = rotateAxis(tiltedNormal, vec3(1.0, 0.0, 0.0), radians(sunPathRotation)); // Apply user-defined tilt from shader options
        vec2 uv = sphereUV(tiltedNormal);
        
        float aberration = 0.002; 
        float r = texture2D(moontex, uv + vec2(aberration, 0.0)).r;
        float g = texture2D(moontex, uv).g;
        float b = texture2D(moontex, uv - vec2(aberration, 0.0)).b;
        vec3 moonColor = vec3(r, g, b);
        
        // --- ANIMATED MOON PHASE SYSTEM ---
        // Minecraft's moon cycle takes 8 days (192,000 ticks)
        float totalWorldTime = float(worldDay) * 24000.0 + float(worldTime);
        float moonCycle = totalWorldTime / 192000.0; 
        
        // Rotate a fake sun vector around the moon to create phases
        float phaseAngle = (moonCycle + 0.25) * 6.2831853; 
        vec3 phaseLightDir = vec3(cos(phaseAngle), 0.0, sin(phaseAngle));
        
        // Calculate how much light hits this part of the moon
        float phaseMask = dot(tiltedNormal, phaseLightDir);
        
        // Soften the terminator line for a realistic shadow gradient
        // Add "Earthshine" (0.03) so the dark side of the moon is still faintly visible
        float illuminated = smoothstep(-0.2, 0.15, phaseMask);
        float moonBrightness = max(illuminated, 0.03);
        
        finalColor *= (1.0 - myNight);
        finalColor += moonColor * HorizonFade * moonBrightness; 
    }

    #ifdef VOLUMETRIC_CLOUDS
    // Apply Rain Darkening
    finalColor *= (1.0 - rainStrength);
    #endif
    
    return finalColor;
}

float distToLine(vec2 p, vec2 a, vec2 b) {
    vec2 pa = p - a;
    vec2 ba = b - a;
    float ba_len = max(dot(ba, ba), 0.00001); // Safely avoids 0.0!
    float h = clamp(dot(pa, ba) / ba_len, 0.0, 1.0);
    return length(pa - ba * h);
}

float lineProgress(vec2 p, vec2 a, vec2 b) {
    vec2 ba = b - a;
    float ba_len = max(dot(ba, ba), 0.00001); // Safely avoids 0.0!
    return clamp(dot(p - a, ba) / ba_len, 0.0, 1.0);
}

vec3 get_sun_glare(float Dist) { // Note: Dist here is VdotL (-1.0 to 1.0)
    float DarkenFactor = 1.0 - rainStrength * (RAIN_SKY_DARKENING * 0.8);
    #ifdef IS_IRIS
        DarkenFactor *= 1.0 - thunderStrength * 0.6;
    #endif
    vec3 realSunPos = normalize(mat3(gbufferModelViewInverse) * sunPosition);
    float sunElev = realSunPos.y;
    float myDay = smoothstep(0.1, 0.3, sunElev);
    float myNight = 1.0 - smoothstep(-0.15, 0.0, sunElev);
    float goldenHour = 1.0 - clamp(myDay + myNight, 0.0, 1.0);
    float mySunrise = goldenHour * step(0.0, realSunPos.x);
    float mySunset  = goldenHour * step(realSunPos.x, 0.0);

    vec3 dayGlare = to_linear(vec3(1.2, 1.1, 1.1)) * vec3(1.05, 0.95, 0.85);
    vec3 sunriseGlare = to_linear(vec3(1.5, 1.1, 0.9));
    vec3 sunsetGlare = to_linear(vec3(1.6, 1.0, 0.8));

    float rise_set_mix = mySunrise / max(goldenHour, 1e-6);
    vec3 goldenHourGlare = mix(sunsetGlare, sunriseGlare, rise_set_mix);
    vec3 finalGlareColor = mix(dayGlare, goldenHourGlare, goldenHour);

    float Visibility = (myDay * 0.6) + goldenHour;
    float clampedDist = max(Dist, 0.0);
    float wideGlow = pow(clampedDist, 5.0) * 0.6;
    float intensePeak = exp(-(1.0 - clampedDist) * 12.0) * 1.5;
    float intensity = (wideGlow + intensePeak) * Visibility;
    return finalGlareColor * DarkenFactor * intensity;
}

vec3 get_stylized_clouds(vec3 ViewPosN, vec3 PlayerPosN, vec3 SunGlare, vec3 SkyColor) {
    // --- 1. COORDINATES (The Skybox Fix) ---
    // We use ViewPosN (Direction), NOT PlayerPos (World Position).
    // This pins the clouds to the sky dome so they don't slide when you walk.
    
    // 1. Get the view ray direction in world space.
    vec3 worldRd = normalize(mat3(gbufferModelViewInverse) * ViewPosN);

    // 2. Find where this ray intersects a flat cloud plane at a fixed height (e.g., y=250).
    float t = (250.0 - cameraPosition.y) / max(worldRd.y, 0.001);
    vec3 worldCloudPos = cameraPosition + worldRd * t;
    
    vec2 CloudUV = worldCloudPos.xz * 0.004;

    vec2 Wind = vec2(frameTimeCounter * CLOUD_SPEED * 0.0001, 0.0);
    vec2 finalUV = CloudUV + Wind;

    // --- 2. SAMPLING (The "Soot" Fix) ---
    float Noise = fbm_clouds(finalUV, CLOUD_QUALITY); 

    // CUTOUT: Your texture has a blue background. We need to hide it.
    // Anything darker than 0.45 becomes transparent.
    // Increase 0.45 if you still see faint squares.
    float Coverage = 0.45; 
    float Density = smoothstep(Coverage, 0.8, Noise); 

    // Optimization: Don't calculate lighting for empty sky
    if (Density <= 0.001) return vec3(0.0);

    // Puffy Modifier
    Density = pow(Density, 0.5); 

    // --- 3. LIGHTING (The Nostalgia Fix) ---
    vec3 realSunPos = normalize(mat3(gbufferModelViewInverse) * sunPosition);
    float VdotL = dot(ViewPosN, realSunPos);
    float myNight = 1.0 - smoothstep(-0.15, 0.0, realSunPos.y);
    float dayFactor = 1.0 - myNight;

    // A. Colors
    // Shadow: Lavender/Blue (Nostalgic), not Gray (Realistic)
    vec3 DayShadow = mix(SkyColor, vec3(0.65, 0.60, 0.85), 0.5);
    vec3 NightShadow = vec3(0.02, 0.02, 0.05);
    vec3 ShadowColor = mix(NightShadow, DayShadow, dayFactor);
    // Darken shadows during rain
    ShadowColor *= (1.0 - rainStrength * 0.6);

    // Light: Warm Creamy White
    vec3 DayLight = vec3(1.0, 0.98, 0.92) + (SunGlare * 0.4);
    vec3 NightLight = vec3(0.1, 0.1, 0.15);
    vec3 SunLight = mix(NightLight, DayLight, dayFactor);

    // B. Silver Lining (Rim Light)
    // Makes the edges glow when looking near the sun
    float Rim = pow(max(VdotL, 0.0), 6.0);
    float SilverLining = Rim * 1.5 * dayFactor * (1.0 - rainStrength);

    // C. Internal Self-Shadowing (Beer's Law)
    float Transmission = exp(-Density * 2.0);
    float Illumination = Transmission + (max(VdotL, 0.0) * 0.2 * dayFactor);

    // --- 4. COMPOSE ---
    vec3 FinalCloud = mix(ShadowColor, SunLight, clamp(Illumination, 0.0, 1.0));
    FinalCloud += SunLight * SilverLining * Density; // Add glow on top

    // Fade clouds at the horizon so they don't clip into the ground
    float HorizonFade = smoothstep(0.0, 0.1, PlayerPosN.y);

    return FinalCloud * Density * HorizonFade;
}

vec3 get_clouds(vec3 ViewPosN, vec3 PlayerPos, vec3 PlayerPosN, vec3 SunGlare, vec3 SkyColor) {
    float cloudDenom = max(PlayerPos.y + length(PlayerPos.xz) / 6.0, 0.001);
    vec2 CloudPos = PlayerPos.xz / cloudDenom;

    const float ACTUAL_CLOUD_SPEED = CLOUD_SPEED / 100.;
    float Animation = float(frameTimeCounter) * ACTUAL_CLOUD_SPEED;
    CloudPos += cameraPosition.xz / 512;
    CloudPos = (CloudPos + Animation) * 32;

    float Noise = fbm_clouds(CloudPos, CLOUD_QUALITY);
    float CloudAmount = CLOUD_AMOUNT / 100.0 + (rainStrength + thunderStrength) / 10;
    Noise *= smoothstep(0, 0.4 - CLOUD_OPACITY, Noise - 0.55 + CloudAmount);
    Noise *= smoothstep(0.0, 0.2, PlayerPosN.y);

    // Ultimate RTX raytraced ptgi 2000 cloud lighting

    float DENSITY = CLOUD_DENSITY + (rainStrength + thunderStrength)*3;
    float Transmittance = exp(-Noise * DENSITY);
    float Absorbtion = fbm_clouds(CloudPos + to_player_pos(sunOrMoonPosN).xz * 8, 2);
    Absorbtion = pow4(Absorbtion * 2);

    float LHeight = sin(sunAngleAtHome * PI * 2);
    vec3 CloudColorRaw = (SKY_GROUND * 2 + SunGlare);
    vec3 CloudColor = CloudColorRaw * 0.25 / PI;

    float VdotL = dot(ViewPosN, sunOrMoonPosN);
    float MiePhase = max(xlf_phase(VdotL, 0.7) * 1.5, 1 / PI);
    CloudColor += SUN_DIRECT * MiePhase * exp(-Absorbtion * DENSITY);

    #ifdef IS_IRIS
        if(lightningBoltPosition.w > 0) {  
            CloudColor += vec3(1) * exp(-DENSITY * distance(lightningBoltPosition.xz / far, PlayerPosN.xz) * 4);
        }
    #endif

    return SkyColor * Transmittance + CloudColor * Noise * DENSITY;
}


vec3 get_nostalgic_sky(vec3 ViewPosN, vec3 SunGlare) {
    float upDot = dot(ViewPosN, gbufferModelView[1].xyz);
    float upPos = max(upDot, 0.0); // clamped vertical looking direction

    // --- 1. Define The Palettes ---
    
    // "Summer Day" Palette (Nostalgic, vibrant)
    vec3 dayZenith   = to_linear(vec3(0.15, 0.05, 0.95)); // Deep saturated blue
    vec3 dayHorizon  = to_linear(vec3(0.75, 0.85, 0.95)); // Soft cyan/white haze
    vec3 dayGround   = to_linear(vec3(0.85, 0.80, 0.75)); // Warm creamy bottom
    
    // "Memory Sunset" Palette (Vaporwave/Lo-fi aesthetic)
    vec3 setZenith   = to_linear(vec3(0.25, 0.10, 0.40)); // Deep Purple
    vec3 setHorizon  = to_linear(vec3(0.95, 0.50, 0.30)); // Hot Pink/Orange
    vec3 setGround   = to_linear(vec3(0.40, 0.20, 0.35)); // Faded plum

    // "Midnight" Palette
    vec3 nightZenith = to_linear(vec3(0.01, 0.02, 0.08));
    vec3 nightHorizon= to_linear(vec3(0.05, 0.10, 0.20));

    // --- 2. Calculate Gradients ---

    // Use your existing fogify for a nice non-linear curve
    // 0.25 controls how "high" the horizon haze reaches
    float skyGradient = fogify(upPos, 0.15); 
    
    vec3 DayColor = mix(dayZenith, dayHorizon, skyGradient);
    // Add a creamy band right at the bottom
    DayColor = mix(DayColor, dayGround, pow(skyGradient, 4.0)); 

    vec3 SetColor = mix(setZenith, setHorizon, skyGradient);
    SetColor = mix(SetColor, setGround, pow(skyGradient, 3.0));

    vec3 NightColor = mix(nightZenith, nightHorizon, skyGradient);

    // --- 3. Atmospheric Scattering (The "Glow") ---
    
    // Determine where the sun is
    // --- CALCULATE TIME OF DAY FROM SUN VECTOR ---
    vec3 realSunPos = normalize(mat3(gbufferModelViewInverse) * sunPosition);
    float sunDot = dot(ViewPosN, realSunPos); 
    
    float sunElev = realSunPos.y;
    float myDay = smoothstep(0.1, 0.3, sunElev);
    float myNight = 1.0 - smoothstep(-0.15, 0.0, sunElev);
    float goldenHour = 1.0 - clamp(myDay + myNight, 0.0, 1.0);
    
    // Create a large, soft halo around the sun (Mie scattering approximation)
    float sunScat = 1.0 / (1.001 - sunDot); // Standard scattering curve
    sunScat = fogify(max(sunDot, 0.0), 0.05) * 0.5; // Softened using your fog function
    
    // Tint the scattering based on time of day (Golden hour boost)
    vec3 scatterColor = mix(vec3(1.0), vec3(1.0, 0.7, 0.4), goldenHour);
    
    // --- 4. Mix Time of Day ---
    
    // Blend Day -> Sunset
    float sunsetMix = smoothstep(0.0, 1.0, goldenHour);
    vec3 mixedSky = mix(DayColor, SetColor, sunsetMix);
    
    // --- TERMINATOR ZONE (Earth's Shadow & Belt of Venus) ---
    vec2 antiSunDirXZ = length(realSunPos.xz) > 0.0001 ? -normalize(realSunPos.xz) : vec2(1.0, 0.0);
    vec2 viewDirXZ = length(ViewPosN.xz) > 0.0001 ? normalize(ViewPosN.xz) : vec2(1.0, 0.0);
    float antiSunDot = max(dot(viewDirXZ, antiSunDirXZ), 0.0);
    
    float terminatorIntensity = pow(antiSunDot, 1.5) * goldenHour;
    float terminatorHeight = 0.05 - sunElev * 0.3; // Rises as the sun sets
    
    float earthShadowMask = 1.0 - smoothstep(terminatorHeight - 0.02, terminatorHeight + 0.05, upPos);
    float venusBeltMask = smoothstep(terminatorHeight - 0.02, terminatorHeight + 0.05, upPos) * 
                          (1.0 - smoothstep(terminatorHeight + 0.02, terminatorHeight + 0.15, upPos));
                          
    vec3 earthShadowColor = vec3(0.02, 0.03, 0.08); // Dark blueish-purple
    vec3 venusBeltColor = vec3(0.85, 0.35, 0.45);   // Vibrant pink/magenta
    
    mixedSky = mix(mixedSky, earthShadowColor, earthShadowMask * terminatorIntensity * 0.8);
    mixedSky += venusBeltColor * venusBeltMask * terminatorIntensity * 0.5;

    // Blend Result -> Night
    mixedSky = mix(mixedSky, NightColor, myNight);

    // --- TWILIGHT ARCH (Sun's Glow below the horizon) ---
    vec2 sunDirXZ = length(realSunPos.xz) > 0.0001 ? normalize(realSunPos.xz) : vec2(1.0, 0.0);
    float sunHorizonDot = max(dot(viewDirXZ, sunDirXZ), 0.0);
    // Twilight peaks when sun is just below the horizon (-0.1 to 0.0)
    float twilightTime = smoothstep(-0.15, -0.02, sunElev) * (1.0 - smoothstep(-0.05, 0.05, sunElev));
    float twilightArch = pow(sunHorizonDot, 3.0) * (1.0 - smoothstep(-0.05, 0.15, upPos));
    vec3 twilightColor = vec3(1.0, 0.35, 0.15); // Fiery orange/red twilight
    mixedSky += twilightColor * twilightArch * twilightTime * 1.2;

    // Add the sun glare passed from function arguments + calculated scattering
    vec3 finalSky = mixedSky + (SunGlare * 0.5) + (scatterColor * sunScat * 0.1 * (1.0 - myNight));

    return finalSky;
}


vec3 get_sky(vec3 ViewPosN, vec3 SunGlare) {
    #ifdef OLD_SKY
    float upDot = dot(ViewPosN, gbufferModelView[1].xyz) + 0.1; //not much, what's up with you?

    vec3 MixedColor = mix(SKY_TOP, SKY_GROUND + SunGlare, fogify(max(upDot, 0.0), 0.03));
    return MixedColor;
    #else
    return get_nostalgic_sky(ViewPosN, SunGlare);
    #endif
}

float get_shooting_star_end_single(vec3 PlayerPos, float idx) {
    float t = frameTimeCounter /7.0;

    float period = 1.0;

    // Offset time per star
    float tOff = t + idx * 19.37;

    float local = mod(tOff, period);

    float act = smoothstep(0.0, 0.2, local)
              * (1.0 - smoothstep(1.2, 1.5, local));

    if (act <= 0.0) return 0.0;

    float seed = floor(tOff / period) + idx * 31.0;

    // Random gate (End should be sparse)
    if (random(vec2(seed, idx)) < 0.55) return 0.0;

    vec2 rnd = vec2(
        random(vec2(seed, seed + 1.0)),
        random(vec2(seed + 2.0, seed + 3.0))
    );

    vec3 Sky = normalize(PlayerPos);
    vec2 uv = Sky.xz / max(0.001, Sky.y);

    vec2 dir = normalize(vec2(rnd.y * 2.0 - 1.0, -rnd.x));

    float travel = local * SHOOTING_STAR_LIFETIME * 10;

    vec2 start = rnd * 2.0 - 1.0;
    vec2 end   = start + dir * travel;

    float lifetime = 1.5;
    float tNorm = clamp(local / lifetime, 0.0, 1.0);

    float headFade = 1.0 - smoothstep(0.45, 1.0, tNorm);
    float prog = lineProgress(uv, start, end);

    float trailFadeSeg = smoothstep(tNorm, tNorm + 0.25, prog);

    float d = distToLine(uv, start, end);
    float trail = exp(-d * 920.0) * trailFadeSeg;

    float head = exp(-length(uv - end) * 80.0) * headFade;

    trail *= mix(1.0, 0.5, tNorm);
    head  *= mix(1.0, 1.3, smoothstep(0.5, 0.8, tNorm));

    return (trail * 0.6 + head) * act * STAR_STRENGTH/5;
}

float get_shooting_stars(vec3 PlayerPos){
    //adjust timing
    float t =frameTimeCounter * SHOOTING_STAR_SPEED;
    float period =SHOOTING_STAR_PERIOD;
    float local =mod(t,period);

    //only visible for a short time
    float act = smoothstep(0.0,0.2,local) * (1.0 - smoothstep(1.2,1.5,local));

    if (act <= 0.0) return 0.0;

    //random seed per event
    float seed =floor(t/period);
    vec2 rnd=vec2(random(vec2(seed,seed+1.0)),
    random(vec2(seed+2.0,seed+3.0)));

    //sky projection

    vec3 Sky =normalize(PlayerPos);
    vec2 uv =Sky.xz / max(0.001,Sky.y);

    //direction
    vec2 dir=normalize(vec2(rnd.y *2.0 -1.0,rnd.y * -1.0));

    //motion 
    float travel = local * SHOOTING_STAR_LIFETIME;
    vec2 start =rnd * 2.0 -1.0;
    vec2 end = start + dir * travel;

    float lifetime = 1.5;              // total visible duration
    float tNorm = clamp(local / lifetime, 0.0, 1.0);
    float headFade = 1.0 - smoothstep(0.45, 1.0, tNorm);
    float prog = lineProgress(uv, start, end);

    // Fade from back to front
    float trailFadeSeg = smoothstep(tNorm, tNorm + 0.25, prog);

    

    //trail
    float d =distToLine(uv,start,end);
    float trail = exp(-d * 920.0) * trailFadeSeg;

    //head
    float head  = exp(-length(uv - end) * 80.0) * headFade;

    trail *= mix(1.0, 0.5, tNorm);

    head *= mix(1.0, 1.3, smoothstep(0.5, 0.8, tNorm));

    vec3 realSunPos = normalize(mat3(gbufferModelViewInverse) * sunPosition);
    float myNight = 1.0 - smoothstep(-0.15, 0.0, realSunPos.y);
    return (trail * 0.6 + head) * act * myNight * STAR_STRENGTH /5;
}

float get_shooting_stars_end(vec3 PlayerPos){
    float stars = 0.0;

    const int STAR_COUNT = 30; // 2–3 is perfect for the End

    for (int i = 0; i < STAR_COUNT; i++) {
         stars += get_shooting_star_end_single(PlayerPos, float(i));
    }

    // Soft clamp (End light should never blow out)
    stars = 1.0 - exp(-stars);

    return stars;
}

vec3 get_stars(vec3 PlayerPos) {
    float starDenom = max(PlayerPos.y + length(PlayerPos.xz), 0.001);
    vec3 BaseCoord = PlayerPos / starDenom;
    BaseCoord.x += frameTimeCounter * 0.001;
    const float ACTUAL_STAR_SIZE = STAR_SIZE * 86.0;

    vec3 scaledCoord = BaseCoord * ACTUAL_STAR_SIZE;
    vec3 cellID = floor(scaledCoord);
    vec2 localUV = fract(scaledCoord.xz) - 0.5; // Centers our coordinate in the middle of the cell

    float Visibility = smoothstep(0.0, 0.1, BaseCoord.y); // fade near horizon
    vec3 realSunPos = normalize(mat3(gbufferModelViewInverse) * sunPosition);
    float myNight = 1.0 - smoothstep(-0.15, 0.0, realSunPos.y);
    #ifdef DIMENSION_OVERWORLD
    Visibility *= myNight;
    #endif

    // Make stars soft, glowing, and round instead of perfectly square blocks
    float dist = length(localUV);
    float shape = smoothstep(0.5, 0.0, dist) * exp(-dist * 5.0);

    // Base star intensity
    float base = max(0.0, random(cellID.xz) - 0.9890) * 50.0 * Visibility * STAR_STRENGTH * shape;

    // --- Add pulsing ---
    // Unique offset per star
    float phase = random(cellID.xy) * 6.2831; // 0..2π
    float pulse = 0.5 + 1.5 * sin(frameTimeCounter * 10.0 + phase); // oscillates 0..1
    float amp = 0.3 + 0.7 * random(cellID.xy); // 0.3..1.0
    base *= max(0.0, 1.0 - amp + amp * pulse);

    // --- Add Color Variance ---
    vec3 starColor = vec3(1.0);
    float colorSeed = random(cellID.xy + vec2(12.0, 34.0));
    
    if (colorSeed > 0.75) {
        starColor = vec3(0.65, 0.85, 1.0); // Blueish
    } else if (colorSeed < 0.25) {
        starColor = vec3(1.0, 0.85, 0.65); // Warm/Orange
    } else if (colorSeed > 0.4 && colorSeed < 0.5) {
        starColor = vec3(0.9, 0.95, 1.0); // Very slight blue
    }

    // Fix: removed the broken clamp(base, 0.2, base) which caused a glowing sky bug
    return starColor * base;
}

vec3 get_aurora(vec3 PlayerPosN, float Dither) {
    if(precipitationSmooth <= 1.01) return vec3(0);
    
    vec3 realSunPos = normalize(mat3(gbufferModelViewInverse) * sunPosition);
    float myNight = 1.0 - smoothstep(-0.15, 0.0, realSunPos.y);
    float AuroraStrength = AURORA_STRENGTH * myNight;
    #ifndef AURORA_EVERYWHERE
        AuroraStrength *= precipitationSmooth - 1;
    #endif
    
    const vec3 COLOR_TOP = pow(vec3(28, 255, 218) / 255.0, vec3(2.2));
    const vec3 COLOR_BOTTOM = pow(vec3(122, 255, 28) / 255.0, vec3(2.2));

    // Calculate intersection with aurora plane
    const float PLANE_TOP = 10.0 + AURORA_HEIGHT;
    const float PLANE_BOTTOM = 10.0;

    float safeAuroraY = abs(PlayerPosN.y) < 0.0001 ? (PlayerPosN.y >= 0.0 ? 0.0001 : -0.0001) : PlayerPosN.y;
    vec3 StartPos = PLANE_BOTTOM / safeAuroraY * PlayerPosN; 
    vec3 EndPos = PLANE_TOP / safeAuroraY * PlayerPosN;

    const int SAMPLE_COUNT = 2;

    vec3 Step = (EndPos - StartPos) / SAMPLE_COUNT;
    vec3 Pos = Step * Dither + StartPos;

    vec2 Wind = frameTimeCounter * vec2(0.25, 0.33);

    vec3 AuroraColor = vec3(0);
    for(int i = 1; i <= SAMPLE_COUNT; i++) {
        float Noise = texture2D(noisetex, (Pos.xz - Wind) / vec2(100, 200)).r;

        Noise = pow2(pow4(Noise));
        Noise *= smoothstep(0.0, 0.2, PlayerPosN.y);
        AuroraColor += Noise * mix(COLOR_BOTTOM, COLOR_TOP, smoothstep(0, 1, Dither));

        Pos += Step;
    }

    return AuroraColor * AuroraStrength / SAMPLE_COUNT;
}

float intersectSphere(vec3 ro, vec3 rd, vec3 so, float sr) {
    vec3 oc = ro - so;
    float b = dot(oc, rd);
    float c = dot(oc, oc) - sr * sr;
    float h = b * b - c;
    
    // If h < 0, the ray missed the sphere
    if (h < 0.0) return -1.0;
    
    // Return distance to the intersection
    return -b - sqrt(h);
}


vec3 get_end_sky(vec3 ViewPosN, vec3 PlayerPosN) {
    vec3 worldRo = gbufferModelViewInverse[3].xyz;
    vec3 worldRd = normalize(mat3(gbufferModelViewInverse) * ViewPosN);
    
    // --- 1. JUPITER POSITION (NOW ANIMATED) ---
    // We set a base position, then rotate it around the Y-axis over time
    vec3 baseJupPos = vec3(1500.0, 800.0, 0.0); 
    vec3 jupiterPos = rotateAxis(baseJupPos, vec3(0.0, 1.0, 0.0), frameTimeCounter * ORBIT_SPEED);
    
    // Shrunk slightly so it doesn't take up the *entire* sky when it gets close
    float jupiterRadius = 800.0; 

    // --- 2. NOSTALGIC SUN POSITION ---
    // Pushed further back (Z = 2500) so Jupiter physically passes IN FRONT of it
    vec3 sunPos = vec3(0.0, 1300.0, 2500.0); 
    float sunRadius = 300.0; 

    // Check Intersections
    float distJup = intersectSphere(worldRo, worldRd, jupiterPos, jupiterRadius);
    float distSun = intersectSphere(worldRo, worldRd, sunPos, sunRadius);
    float sunDot = dot(worldRd, normalize(sunPos));

    // --- 3. DRAW CELESTIAL BODIES (With Depth Sorting!) ---
    if (distJup > 0.0 || distSun > 0.0) {
        
        // If we hit Jupiter, AND it's either the only thing we hit OR it's closer than the sun
        if (distJup > 0.0 && (distSun < 0.0 || distJup < distSun)) {
            vec3 worldHitPos = worldRo + (worldRd * distJup);
            vec3 normal = normalize(worldHitPos - jupiterPos);
            
            vec3 tiltedNormal = rotateAxis(normal, vec3(0.8, 1.0, 0.0), radians(90.0));
            vec2 uv = sphereUV(vec3(tiltedNormal.x, tiltedNormal.z, tiltedNormal.y));
            uv.x += frameTimeCounter * 0.005;

            float aberration = 0.003; 
            float r = texture2DLod(jupitertex, uv + vec2(aberration, 0.0),0.0).r;
            float g = texture2DLod(jupitertex, uv,0.0).g;
            float b = texture2DLod(jupitertex, uv - vec2(aberration, 0.0),0.0).b;
            vec3 planetColor = vec3(r, g, b);
            
            // Because lightDirFromSun is dynamic, Jupiter will perfectly silhouette 
            // into a crescent/dark circle when it eclipses the sun!
            vec3 lightDirFromSun = normalize(sunPos - jupiterPos);
            float lighting = max(dot(normal, lightDirFromSun), 0.002) * 0.5; 
            
            float fresnel = pow(1.0 - dot(normal, -worldRd), 4.0);
            return (planetColor * lighting) + (vec3(0.2, 0.1, 0.3) * fresnel); 
        } 
        // Otherwise, if we hit the sun (and it wasn't blocked)
        else if (distSun > 0.0) {
            return vec3(1.0) * 10.0;
        }
    }

    // --- 4. BASE SKY RENDER (Existing code) ---
    const vec3 SkyT = to_linear(vec3(f_END_SKY_T_R, f_END_SKY_T_G, f_END_SKY_T_B));
    const vec3 SkyG1 = to_linear(vec3(f_END_AURORA1_R, f_END_AURORA1_G, f_END_AURORA1_B));
    const vec3 SkyG2 = to_linear(vec3(f_END_AURORA2_R, f_END_AURORA2_G, f_END_AURORA2_B));

    float upDot = dot(ViewPosN, gbufferModelView[1].xyz);
    
    // Sun Halo (Scattering around the star)
    float sunHalo = pow(max(sunDot, 0.0), 20.0) * 2.5;
    vec3 haloColor = vec3(0.6, 0.1, 0.5) * sunHalo; // Magenta/Purple glow around sun

    vec2 RotPos1 = rotate(PlayerPosN.xz, frameTimeCounter * 0.02);
    vec2 RotPos2 = rotate(PlayerPosN.xz, -frameTimeCounter * 0.007);
    float Noise1 = fbm_fast(RotPos1 * 160, 2);
    float Noise2 = fbm_fast(RotPos2 * 280, 2);
    float VerticalFactor = 1.0 - abs(upDot);
    vec3 SkyG = (SkyG1 * Noise1 + SkyG2 * Noise2) * VerticalFactor;

    vec3 Final = SkyT + SkyG * (fogify(upDot + 0.2, 0.05)) + haloColor; 

    float voidFactor = smoothstep(-0.6, 0.1, upDot);
    Final *= voidFactor;
    Final += SkyT * 0.05;
    Final *= max(1.0 - fogify(max(upDot + 0.2, 0), 0.02), 0.01);

    return Final;
}

vec3 get_rainbow(vec3 viewDir) {
    float visibility;
    #if RAINBOW == 1
    visibility = clamp(wetness - rainStrength, 0.0, 1.0);
    #elif RAINBOW == 2
    visibility = 1.0;
    #else
    return vec3(0.0);
    #endif

    if (visibility <= 0.001) return vec3(0.0);

    // Ensure the sun is relatively low, and it's daytime
    vec3 realSunPos = normalize(mat3(gbufferModelViewInverse) * sunPosition);
    float sunFade = smoothstep(0.0, 0.4, realSunPos.y) * smoothstep(0.65, 0.2, realSunPos.y);
    if (sunFade <= 0.001) return vec3(0.0);

    // Rainbows appear exactly opposite to the sun (anti-solar point)
    vec3 antiSunDir = -realSunPos;
    float cosAngle = dot(viewDir, antiSunDir);
    
    // Rainbows are visible around 42 degrees from the anti-solar point.
    // Lowering the base angle makes the circle larger (higher in the sky).
    // Increasing the thickness makes the band wider.
    float baseAngle = 0.65;
    float thickness = 0.06;
    
    if (cosAngle < baseAngle || cosAngle > baseAngle + thickness) return vec3(0.0);

    // Map the angle inside the band to [0.0, 1.0] for the color spectrum
    float t = (cosAngle - baseAngle) / thickness;
    
    // Generate the rainbow spectrum (Red to Violet)
    vec3 color = clamp(vec3(abs(t * 6.0 - 3.0) - 1.0, 2.0 - abs(t * 6.0 - 2.0), 2.0 - abs(t * 6.0 - 4.0)), 0.0, 1.2);
    
    // Soften the edges and fade at the horizon so it doesn't clip into the ground
    float edgeFade = smoothstep(0.0, 0.2, t) * smoothstep(1.0, 0.8, t);
    float horizonFade = smoothstep(-0.05, 0.1, viewDir.y);
    
    return color * visibility * sunFade * edgeFade * horizonFade * 0.4;
}

vec3 get_sky_main(vec3 ViewPosN, vec3 PlayerPosN, vec3 SunGlare, out float cloudTransmittance) {

    cloudTransmittance = 1.0;

    #ifdef DIMENSION_OVERWORLD
        // 1. Get the base nostalgic sky background
        vec3 SkyColor = get_sky(ViewPosN, SunGlare);
        
        // 2. Setup World Coordinates for Volumetrics
        vec3 worldRo = cameraPosition; // Camera World Position
        vec3 worldRd = normalize(mat3(gbufferModelViewInverse) * ViewPosN); // Ray Direction
        // Fix: Use sunPosition instead of shadowLightPosition so the light direction doesn't instantly flip to the moon at sunset
        vec3 sunDir = normalize(mat3(gbufferModelViewInverse) * sunPosition); // Sun Direction
        
        #ifdef VOLUMETRIC_CLOUDS
        SkyColor = get_nostalgic_volumetrics(worldRd, worldRo, sunDir, SkyColor, SunGlare,CLOUD_DIMMER_SKY,cloudTransmittance,false, 0.0);
        #endif
    #elif defined DIMENSION_END
        vec3 SkyColor = get_end_sky(ViewPosN, PlayerPosN);
    #else
        vec3 fogColorL = to_linear(fogColor.rgb);
        fogColorL += 1e-6; // Need to prevent nans when fog is vec3(0)
        vec3 SkyColor = mix(fogColorL, normalize(fogColorL), 0.4) / 3;
    #endif

    return SkyColor;
}
