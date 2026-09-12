vec3 ssr_Block(vec3 RVec, float Dist, vec3 ViewPos, float Fresnel, float WNy, bool IsDH, sampler2D lightmap,vec2 lmcoord,float SkyBrightness,vec3 color) {
    vec3 ScreenPos = vec3(gl_FragCoord.xy * resolutionInv, gl_FragCoord.z);
    vec3 Offset = normalize(view_screen(ViewPos + RVec, IsDH) - ScreenPos);
    vec3 Len = (step(0, Offset) - ScreenPos) / Offset;
    float MinLen = min(Len.x, min(Len.y, Len.z)) / SSR_STEPS;
    Offset *= MinLen;

    float Noise = dither(gl_FragCoord.xy);
    vec3 ExpectedPos = ScreenPos + Offset * Noise;
    for (int i = 1; i <= SSR_STEPS; i++) {
        float RealDepth = get_depth_solid(ExpectedPos.xy, IsDH);
        if (RealDepth < 0.56) {
            break;
        }

        if (ExpectedPos.z > RealDepth) {
            if (ExpectedPos.z - RealDepth > Offset.z * (0.5 * SSR_STEPS)) {
                break;
            }
            for (int j = 1; j <= int(round(Fresnel * 3)); j++) {
                Offset /= 2;
                vec3 EPos1 = ExpectedPos - Offset;
                float RDepth1 = get_depth_solid(EPos1.xy, IsDH);
                if (EPos1.z > RDepth1) {
                    ExpectedPos = EPos1;
                }
            }
            // TINT THE SSR REFLECTIONS BLUE TOO
            vec3 rawSSR = texture2D(gaux1, ExpectedPos.xy).rgb;
            if(IsDH){
                 return clamp(rawSSR ,0.0,1.0);
            }else {
                 float brightness = SSR_BRIGHTNESS - (dayStrength * 0.1) - (sunriseStrength*0.3) - (sunsetStrength * 0.3);
             return clamp(rawSSR * brightness, 0.0, 1.0);
            }
        }
        ExpectedPos += Offset;
    }
    return mix(sky_reflection(RVec, WNy, Dist,ViewPos,lightmap,lmcoord) * 0.02,color,0.4);
}