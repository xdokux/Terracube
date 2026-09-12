const vec2 poisson_disk_2d[] = vec2[8](
        vec2(-0.11995088205640914, 0.719751341508128),
        vec2(0.317022622719358, 0.22113273160666158),
        vec2(-0.26403670704884585, -0.3332036575870605),
        vec2(-0.4956967808947522, 0.1440260614790989),
        vec2(-0.2515255173617287, 0.4485353371596208),
        vec2(0.44577086115163955, 0.4954141319381722),
        vec2(0.18920463723666625, 0.7216180893153676),
        vec2(0.05891867438075504, -0.16082515533796937)
    );

vec3 ssao(vec3 Color, vec3 ViewPos) {
    if (ViewPos.z < -64.) return Color;

    float Depth = -ViewPos.z;
    float dx = dFdx(Depth);
    float dy = dFdy(Depth);
    vec3 Normal = normalize(vec3(dx, dy, (1-dx*dx-dy*dy)));

    float Factor = 0, Hits = 0;

    float Dither = dither(gl_FragCoord.xy) * 2 * PI;

    // Depth-adaptive sample radius
    float AdaptiveScale = SSAO_SCALE * clamp(8.0 / Depth, 0.5, 2.0);

    for (int i = 0; i < 8; i++) {
        const float DEPTH_BIAS = 0.00015;
        vec3 Sample = vec3(rotate(poisson_disk_2d[i], Dither) * AdaptiveScale, DEPTH_BIAS);
        Sample *= sign(dot(Normal, Sample));
        Sample += Normal * 0.05;
        Sample += ViewPos;
        Sample = view_screen(Sample, false);
        if(Sample.xy != clamp(Sample.xy, 0, 1)) continue;
        float RealDepth = texture2D(depthtex0, Sample.xy).x;
        if (RealDepth < 0.56) continue;

        // Depth-aware weighting: reduce AO contribution for distant occluders
        float DepthDiff = abs(Sample.z - RealDepth);
        float RangeCheck = smoothstep(0.0, 1.0, AdaptiveScale * 0.5 / (DepthDiff + 0.001));

        Factor += step(RealDepth, Sample.z) * RangeCheck;
        Hits++;
    }
    Factor /= Hits == 0 ? 1 : Hits;

    // Smoother falloff with distance
    float DistFade = smoothstep(48.0, 16.0, Depth);
    return Color * (1 - Factor * SSAO_STRENGTH * DistFade);
}
