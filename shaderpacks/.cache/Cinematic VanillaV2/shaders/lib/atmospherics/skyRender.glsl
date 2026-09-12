// ============================================================
//  CinematicVanilla V2 - skyRender.glsl
//  Cinematic sky: Rayleigh+Mie atmosphere, improved clouds,
//  dynamic star density, enhanced sunset/dawn palette.
// ============================================================

// ─── Sun/Moon Shape ─────────────────────────────────────────────────────────
float getSunMoonShape(in float skyPosZ){
    return min(1.0, exp2((WORLD_SUN_MOON_SIZE - sqrt(1.0 - skyPosZ * skyPosZ)) * 256.0));
}
float getSunMoonShape(in vec2 skyPos){
    return min(1.0, exp2((WORLD_SUN_MOON_SIZE
         - pow(abs(skyPos.x * skyPos.x * skyPos.x)
             + abs(skyPos.y * skyPos.y * skyPos.y), 0.33333333)) * 256.0));
}

// ─── Mie Scattering Halo ────────────────────────────────────────────────────
// Forward-scattering glow around the sun/moon (Henyey-Greenstein)
float getMieScatter(in float cosTheta){
    const float g  = 0.78, g2 = 0.78 * 0.78;
    float denom = max(0.0001, 1.0 + g2 - 2.0 * g * cosTheta);
    return (1.0 - g2) / (4.0 * 3.14159265 * pow(denom, 1.5)) * 0.004;
}

// ─── Rayleigh Sky ──────────────────────────────────────────────────────────
// Cheap Rayleigh-style atmospheric depth tinting at the horizon
vec3 getRayleighSky(in float nEyePlayerPosY, in vec3 dayCol, in vec3 nightCol){
    float h = saturate(nEyePlayerPosY);
    // Deeper blue at zenith, lighter + more grey at horizon
    vec3 zenith  = dayCol * 1.10;
    vec3 horizon = mix(dayCol * vec3(0.85, 0.90, 1.00), vec3(0.68, 0.78, 0.90), 0.35);
    vec3 sky = mix(horizon, zenith, h * h);
    #ifndef FORCE_DISABLE_DAY_CYCLE
        sky = mix(nightCol, sky, saturate(dayCycleAdjust * 3.0 - 0.5));
    #endif
    return sky;
}

// ─── Cinematic Horizon Glow ─────────────────────────────────────────────────
// Multi-band: warm orange low band + red upper band + purple anti-solar
vec3 getCinematicHorizonGlow(in float nEyePlayerPosY, in float cosA){
    #ifndef FORCE_DISABLE_DAY_CYCLE
        float tw = 1.0 - abs(dayCycleAdjust * 2.0 - 1.0);
        tw *= tw;
        float hBand    = exp2(-abs(nEyePlayerPosY) * 6.0);
        float lowBand  = exp2(-abs(nEyePlayerPosY) * 20.0);

        // Solar side: warm orange glow that bleeds up
        vec3 solar   = vec3(1.00, 0.40, 0.08) * max(0.0, cosA);
        // Anti-solar: purple/blue opposite the sun
        vec3 antisol = vec3(0.52, 0.18, 0.48) * max(0.0, -cosA);
        // Deep red strip at horizon (like a real sunset)
        vec3 redLine  = vec3(1.00, 0.18, 0.04) * lowBand;

        vec3 glow = (solar * hBand * 0.60 + antisol * hBand * 0.25 + redLine * 0.35) * tw;
        return glow;
    #else
        return vec3(0.0);
    #endif
}

// ─── Stars ──────────────────────────────────────────────────────────────────
// Simple pseudo-random star field — denser on HIGH preset
float getStarField(in vec3 dir){
    // Hash the sky direction into a 0..1 value
    vec3 d = normalize(dir);
    float h = fract(sin(dot(d.xz, vec2(127.1, 311.7))) * 43758.5453);
    float size = 0.995; // threshold: higher = fewer stars
    return step(size, h) * saturate(-d.y + 0.05) * 2.0;
}

// ─── Cloud Rendering ────────────────────────────────────────────────────────
#if CLOUD_TYPE != 0 && !defined FORCE_DISABLE_CLOUDS && defined WORLD_LIGHT
    const uint  skyBoxCloudSteps = uint(SKYBOX_CLOUD_STEPS);
    const float cloudStepSize    = 1.0 / skyBoxCloudSteps;
    const float depthSize        = SKYBOX_CLOUD_DEPTH * cloudStepSize;

    vec2 cloudParallaxDynamic(in vec2 start, in vec2 cameraPos){
        vec2 end = start * depthSize;
        start += cameraPos * 0.0625;
        vec2 cloudData = vec2(0);
        for(uint i = 1u; i <= skyBoxCloudSteps; i++){
            vec2 cloudMap = texelFetch(colortex0, ivec2(start) & 255, 0).xy;
            if(cloudMap.x > 0.5) cloudData.x = float(i);
            if(cloudMap.y > 0.5) cloudData.y = float(i);
            start -= end;
        }
        return cloudData;
    }

    vec3 getSkyClouds(in vec3 nEyePlayerPos, in vec3 currSkyCol){
        float cloudHeightFade = nEyePlayerPos.y - 0.1;
        #ifdef FORCE_DISABLE_WEATHER
            cloudHeightFade *= 6.0;
        #else
            cloudHeightFade -= rainStrength * 0.2;
            cloudHeightFade *= 6.0 - rainStrength * 5.0;
        #endif
        if(cloudHeightFade <= 0.0) return currSkyCol;
        cloudHeightFade = min(1.0, cloudHeightFade);

        vec2 planeUv  = nEyePlayerPos.xz * (6.0 / nEyePlayerPos.y);
        vec2 planePos = vec2(cameraPosition.x + fragmentFrameTime * 0.8, cameraPosition.z);
        vec2 cloudData = cloudParallaxDynamic(planeUv, planePos);

        #ifdef DOUBLE_LAYERED_CLOUDS
            cloudData = max(cloudParallaxDynamic(planeUv * 2.0, planePos).yx * 0.25, cloudData);
        #endif

        #ifdef DYNAMIC_CLOUDS
            float fadeTime = saturate(sin(fragmentFrameTime * FADE_SPEED) * 0.8 + 0.5);
            float clouds   = mix(mix(cloudData.x, cloudData.y, fadeTime),
                                 max(cloudData.x, cloudData.y), rainStrength);
        #else
            float clouds = cloudData.x;
        #endif

        clouds = clouds / float(skyBoxCloudSteps);

        // Twilight cloud edge warming
        #ifndef FORCE_DISABLE_DAY_CYCLE
            float tw = 1.0 - abs(dayCycleAdjust * 2.0 - 1.0);
            tw = tw * tw;
            vec3 cloudEdgeTint = mix(vec3(1.0), vec3(1.20, 0.75, 0.50), tw * 0.5);
        #else
            vec3 cloudEdgeTint = vec3(1.0);
        #endif

        vec3 cloudCol = mix(currSkyCol, currSkyCol * 1.6 * cloudEdgeTint, clouds * cloudHeightFade);
        return cloudCol;
    }
#endif
