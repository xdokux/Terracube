vec3 rsm(vec3 PlayerPos, vec3 Normal, vec3 LightColor) {
    if (isOutdoorsSmooth < 0.001) return vec3(0);
    if (isEyeInWater == 1) return vec3(0);

    float Fade = shadow_fade(PlayerPos, shadowDistanceDH);
    if(Fade > 0.99) return vec3(0);

    float CloudCoverage = cloud_shadows(PlayerPos + cameraPosition);
    if(CloudCoverage < 0.01) return vec3(0);

    vec3 ShadowPos = player_shadow(PlayerPos);

    vec3 ShadowNormal = mat3(shadowModelView) * (mat3(gbufferModelViewInverse) * Normal);
    vec3 Sum = vec3(0);

    vec2 Pos = gl_FragCoord.xy;
    float Dither = blue_noise(Pos, true).r * TAU;
    
    for (int i = 1; i <= RSM_SAMPLE_COUNT; i++) {
        vec2 Offset = rotate(vogel_disk[i], Dither) * shadowTexSize * 96;
        
        Offset *= sign(dot(Offset, ShadowNormal.xy));

        vec3 OffsetPos = ShadowPos + vec3(Offset, 0);
        vec3 SamplePos = distort(OffsetPos) * 0.5 + 0.5;
        float RealDepth = texture(shadowtex1, SamplePos.xy).x;
        RealDepth = (RealDepth * 2 - 1) / 0.2;
        if (RealDepth < ShadowPos.z) continue;

        OffsetPos.z = RealDepth;

        float Dist = distance(OffsetPos, ShadowPos);
        float Flux = pow1_33_f(max(1 - Dist / (shadowTexSize * 96), 0));

        if (Flux < 0.0001) continue;

        vec3 SampleNormal = decodeUnitVector(texture(shadowcolor1, SamplePos.xy).rg * 2 - 1);

        vec3 RayDir = normalize(OffsetPos - ShadowPos);
        RayDir.z *= -1;
        Flux *= max(0, dot(RayDir, ShadowNormal.xyz));
        RayDir *= -1;
        Flux *= max(0, dot(RayDir, SampleNormal));

        if (Flux < 0.0001) continue;

        vec3 ShadowColor = texture(shadowcolor0, SamplePos.xy).rgb;
        
        Sum += ShadowColor * Flux;
    }
    vec3 Rsm = Sum * LightColor / RSM_SAMPLE_COUNT * isOutdoorsSmooth * CloudCoverage * (1 - Fade);
    
    return Rsm;
}

float[5] weights = float[5](0.13298, 0.12579, 0.0866, 0.05455, 0.03316);
vec4 gi_denoise(sampler2D Sampler, vec2 Texcoord, vec2 direction, float CurrentDepth, bool IsDH) {
    vec4 color = vec4(0);
    float TotalWeight = 0;
    float CurrentData = texture(colortex1, Texcoord, 0).w;
    CurrentDepth = l_depth(CurrentDepth, IsDH);
    vec3 CurrentNormal = decodeUnitVector(unpackUnorm2x8(CurrentData) * 2 - 1);

    const int BLUR_SIZE = 3;
    const float MAGIC_NUMBER = 2;

    for (int i = -BLUR_SIZE; i <= BLUR_SIZE; i++) {
        vec2 OffsetUV = Texcoord + i * direction * MAGIC_NUMBER * resolutionInv;
        vec4 OffsetColor = texture(Sampler, OffsetUV, 0);

        float OffsetWeight = 1; //weights[abs(i)];
        
        bool IsOffsetDH;
        float OffsetDepth = get_depth(OffsetUV, IsOffsetDH);
        OffsetDepth = l_depth(OffsetDepth, IsOffsetDH);
        OffsetWeight *= pow4(clamp(1 - abs(CurrentDepth - OffsetDepth), 0, 1));

        float OffsetData = texture(colortex1, OffsetUV, 0).w;
        vec3 OffsetNormal = decodeUnitVector(unpackUnorm2x8(OffsetData) * 2 - 1);
        OffsetWeight *= pow4(max(dot(CurrentNormal, OffsetNormal), 0));

        color += OffsetColor * OffsetWeight;
        TotalWeight += OffsetWeight;
    }
    return color / TotalWeight;
}
