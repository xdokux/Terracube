// VHS noise helpers
float rand(vec2 co) {
    return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
}
// VHS scanline effect
float scanline(vec2 uv) {
    return 0.9 + SCANLINES_THICKNESS * sin(uv.y * viewHeight * .5 + frameTimeCounter * 60.0);
}

vec3 anamorphicEffect(vec3 color, vec2 uv) {
    // Chromatic aberration: sample nearby pixels around UV
    float shift = SHIFT;
    float noise = rand(uv + frameTimeCounter);
    vec2 offset = vec2(shift * noise, 0.0);

    // Fetch slightly offset versions (using color as base, not overwriting)
    float r = texture(colortex0, uv + offset).r;
    float g = texture(colortex0, uv).g;
    float b = texture(colortex0, uv - offset).b;
    vec3 aberr = vec3(r, g, b);

    // Mix aberration with the original color
    color = mix(color, aberr, 0.4);

    #ifdef SCANLINES
    // Add scanline flicker
    color *= scanline(uv);
    #endif

    // Add ghost horizontal flare (anamorphic streak)
    vec3 flare = vec3(0.0);
    for (float i = -3.0; i <= 3.0; i++) {
        flare += texture(colortex0, uv + vec2(i * 0.002, 0.0)).rgb * 0.05;
    }
    color += flare * 0.15;

    // Add subtle film grain
    color += (rand(uv * viewHeight) - 0.5) * 0.02;

    return color;
}
