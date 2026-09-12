#include "/lib/all_the_libs.glsl"

varying vec2 texcoord;

#include "/global/post/taa.glsl"
#include "/global/post/cas.glsl"

vec3 film_grain(vec3 Color, vec2 Pos) {
    Pos.x += fract(float(frameCounter) / 4.14159) * 234;
    Pos.y -= fract(float(frameCounter) / 5.49382) * 567;
    Color += (texture2D(noisetex, Pos.xy / 255).rgb - 0.5) * FILM_GRAIN_STRENGTH;
    return Color;
}

vec3 apply_vignette(vec3 Color, vec2 Pos) {
    Pos = Pos - 0.5;
    Pos *= VIGNETTE_OPACITY;
    float Strength = len2(Pos);
    Strength = pow(Strength, 2 - VIGNETTE_FALLOFF);
    Color *= 1 - min(Strength, 1);
    return Color;
}

#ifdef DOF
vec3 apply_dof(sampler2D tex, vec2 uv) {
    float CenterDepth = texture2D(depthtex0, vec2(0.5)).x;
    float FragDepth = texture2D(depthtex0, uv).x;

    float CenterDist = ld_exact(CenterDepth, near, far);
    float FragDist = ld_exact(FragDepth, near, far);

    float CoC = abs(FragDist - CenterDist) / FragDist;
    CoC = clamp(CoC * DOF_STRENGTH * 2.0, 0.0, 0.03);

    if (CoC < 0.0005) {
        #ifdef IMAGE_SHARPENING
        return CAS(tex);
        #else
        return texture2D(tex, uv).rgb;
        #endif
    }

    vec3 Color = vec3(0.0);
    float TotalWeight = 0.0;
    float Angle = dither(gl_FragCoord.xy) * 2 * PI;
    for (int i = 0; i < DOF_QUALITY; i++) {
        float T = float(i) / float(DOF_QUALITY) * 2 * PI + Angle;
        float R = sqrt(float(i + 1) / float(DOF_QUALITY)) * CoC;
        vec2 Offset = vec2(cos(T), sin(T)) * R;
        // Correct for aspect ratio
        Offset.x *= resolution.y / resolution.x;
        Color += texture2D(tex, uv + Offset).rgb;
        TotalWeight += 1.0;
    }
    return Color / TotalWeight;
}
#endif

// CAS

void main() {
    #ifdef DOF
    vec4 Color = vec4(apply_dof(colortex0, texcoord), 1);
    #elif defined IMAGE_SHARPENING
    vec4 Color = vec4(CAS(colortex0), 1);
    #else
    vec4 Color = texture2D(colortex0, texcoord);
    #endif

    Color.rgb = apply_vibrance(Color.rgb, VIBRANCE);
    Color.rgb = apply_saturation(Color.rgb, SATURATION);
    Color.rgb = apply_contrast(Color.rgb, CONTRAST);

    vec3 MinBright = vec3(TONEMAP_MIN_R, TONEMAP_MIN_G, TONEMAP_MIN_B);
    Color.rgb = max(Color.rgb, MinBright);

    #ifdef FILM_GRAIN
    Color.rgb = film_grain(Color.rgb, gl_FragCoord.xy);
    #endif

    Color.rgb = apply_vignette(Color.rgb, texcoord);

    Color.xyz += (bayer8(gl_FragCoord.xy) - 0.5) / 255;

    gl_FragData[0] = Color;
}
