float vws_hash(float n) {
    return fract(sin(n * 12.9898) * 43758.5453);
}

float vws_seg_dist(vec2 P, vec2 A, vec2 B) {
    vec2 PA = P - A;
    vec2 BA = B - A;
    float h = clamp(dot(PA, BA) / max(dot(BA, BA), 1e-4), 0.0, 1.0);
    return length(PA - BA * h);
}

vec2 get_wind_offset(float localSpeed, float rainMultiplier, float variationAmplitude) {
    float t = frameTimeCounter;
    float constantSpeed = localSpeed * float(WIND_GLOBAL_SPEED);
    float angleRad = radians(float(WIND_BASE_ANGLE));
    vec2 baseDir = vec2(sin(angleRad), cos(angleRad)); 
    float varSpeed = float(WIND_BASE_ANGLE_VARIATION);
    float slowT = t * 0.02 * varSpeed;
    float currentIntensity = mix(1.0, rainMultiplier, rainStrength);
    float sway = sin(slowT * 1.3) * cos(slowT * 0.8);
    vec2 wandering = baseDir * sway * variationAmplitude * currentIntensity * constantSpeed;
    return -((baseDir * t * constantSpeed) + wandering);
}

vec2 get_wind_vector(float rainMultiplier, float variationAmplitude) {
    float t = frameTimeCounter;
    float currentForce = mix(1.0, rainMultiplier, rainStrength) * float(WIND_GLOBAL_SPEED);
    float angleRad = radians(float(WIND_BASE_ANGLE));
    vec2 baseDir = vec2(sin(angleRad), cos(angleRad)) * currentForce;
    float varSpeed = float(WIND_BASE_ANGLE_VARIATION);
    float slowT = t * 0.02 * varSpeed;
    float sway = cos(slowT * 1.3) * 1.3 - sin(slowT * 0.8) * 0.8;
    vec2 wanderingDir = baseDir * sway * variationAmplitude * 0.02 * varSpeed;
    return baseDir + wanderingDir;
}

vec3 velocity_wind_streaks(vec3 ViewPosN, vec3 PlayerPosN, vec3 SkyColor) {
    #if defined(HELIOS_WIND_STREAKS) && defined(DIMENSION_OVERWORLD)
    if (isOutdoorsSmooth < 0.1) return vec3(0.0);

    float timeOfDayStrength = dayStrength + sunriseStrength * 0.6 + sunsetStrength * 0.6
                              + nightStrength * HELIOS_WIND_STREAK_NIGHT_FACTOR;
    if (timeOfDayStrength < 0.05) return vec3(0.0);

    if (PlayerPosN.y <= 0.05) return vec3(0.0);

    const float STREAK_ALTITUDE = 80.0;
    vec3 planePos = PlayerPosN * (STREAK_ALTITUDE / PlayerPosN.y);

    vec2 windVec = get_wind_vector(1.5, 10.0);
    vec2 baseWindDir = normalize(windVec + vec2(1e-4));
    vec2 windOffset = get_wind_offset(0.8, 1.5, 10.0);

    vec2 uv = planePos.xz + windOffset * 0.1;

    vec3 TotalColor = vec3(0.0);
    float interval = 45.0 / max(HELIOS_WIND_STREAK_FREQUENCY * timeOfDayStrength, 0.01);
    float duration = HELIOS_WIND_STREAK_DURATION;

    for (int stream = 0; stream < 3; stream++) {
        float streamOffset = float(stream) * (interval * 0.33);
        float timeVar = frameTimeCounter + streamOffset;
        float spawnIndex = floor(timeVar / interval);
        float timeInCycle = fract(timeVar / interval) * interval;
        if (timeInCycle > duration) continue;

        float progress = timeInCycle / duration;

        float streamSeed = float(stream) * 17.3;
        float s1 = vws_hash(spawnIndex * 1.7 + 0.3 + streamSeed);
        float s2 = vws_hash(spawnIndex * 3.1 + 1.7 + streamSeed);
        float s3 = vws_hash(spawnIndex * 5.9 + 4.2 + streamSeed);
        float s4 = vws_hash(spawnIndex * 7.3 + 9.1 + streamSeed);
        float s5 = vws_hash(spawnIndex * 2.1 + 2.2 + streamSeed);

        float angleVar = (s1 - 0.5) * 0.4;
        vec2 dir = normalize(baseWindDir + vec2(sin(angleVar), cos(angleVar)) * 0.25);
        vec2 perp = vec2(-dir.y, dir.x);

        float pathLength = 140.0 + s5 * 90.0;
        vec2 center = vec2(s2 - 0.5, s3 - 0.5) * 120.0;
        vec2 start = center - dir * (pathLength * 0.5);
        vec2 end = center + dir * (pathLength * 0.5);

        vec2 head = mix(start, end, progress);

        float swirlPhase = s4 * TAU;
        float swirlAmp = 10.0 + s5 * 8.0;
        vec2 swirlOffset = perp * sin(progress * 6.28 * 2.5 + swirlPhase) * swirlAmp;
        head += swirlOffset;

        float trailLen = 0.22;
        float trailProgress = max(progress - trailLen, 0.0);
        vec2 tail = mix(start, end, trailProgress);
        tail += perp * sin(trailProgress * 6.28 * 2.5 + swirlPhase) * swirlAmp;

        float dist = vws_seg_dist(uv, tail, head);

        float thickness = 3.5 * HELIOS_WIND_STREAK_THICKNESS;
        float lineAlpha = smoothstep(thickness, 0.0, dist);

        float lifeFade = smoothstep(0.0, 0.12, progress) * smoothstep(1.0, 0.8, progress);
        lineAlpha *= lifeFade;

        float camDist = length(planePos);
        float distFade = 1.0 - smoothstep(200.0, 450.0, camDist);
        lineAlpha *= distFade;

        float altitudeFade = smoothstep(0.05, 0.25, PlayerPosN.y);
        lineAlpha *= altitudeFade;

        float brightness = HELIOS_WIND_STREAK_BRIGHTNESS * timeOfDayStrength * 0.9;

        vec3 streakColor = mix(vec3(0.85, 0.92, 1.0), vec3(1.0, 0.95, 0.85), dayStrength);
        streakColor = mix(streakColor, vec3(0.8, 0.85, 1.0), nightStrength * 0.5);
        streakColor = mix(streakColor, SkyColor, 1.0 - distFade);

        TotalColor += streakColor * lineAlpha * brightness;
    }

    return TotalColor;
    #else
    return vec3(0.0);
    #endif
}
