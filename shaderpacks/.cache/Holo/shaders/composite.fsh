#version 120

// ============================================================
//  HOLOGRAM SHADER - composite.fsh
//  Sci-fi holografik projeksiyon: mavi/cyan renk tonu,
//  edge glow, projeksiyon titremesi
// ============================================================

uniform sampler2D colortex0;
uniform float frameTimeCounter;
uniform float viewWidth;
uniform float viewHeight;

varying vec2 texcoord;

float hash(float n) { return fract(sin(n) * 43758.5453); }
float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

// Edge detection (for glowing outlines)
vec3 edgeGlow(vec2 uv) {
    vec2 px = vec2(1.0 / viewWidth, 1.0 / viewHeight);

    vec3 c = texture2D(colortex0, uv).rgb;
    vec3 r = texture2D(colortex0, uv + vec2(px.x, 0.0)).rgb;
    vec3 d = texture2D(colortex0, uv + vec2(0.0, px.y)).rgb;

    float luma_c = dot(c, vec3(0.299, 0.587, 0.114));
    float luma_r = dot(r, vec3(0.299, 0.587, 0.114));
    float luma_d = dot(d, vec3(0.299, 0.587, 0.114));

    float edge = abs(luma_c - luma_r) + abs(luma_c - luma_d);

    return vec3(edge * 3.0);
}

void main() {
    float t = frameTimeCounter;
    vec2 uv = texcoord;

    vec3 base = texture2D(colortex0, uv).rgb;

    // Luminance
    float luma = dot(base, vec3(0.299, 0.587, 0.114));

    // Slight contrast boost before coloring
    luma = (luma - 0.5) * 1.35 + 0.5;
    luma = clamp(luma, 0.0, 1.0);

    // Convert to hologram colors
    vec3 holoColor = vec3(
        0.1 + luma * 0.3,
        0.7 + luma * 0.4,
        1.0
    );

    holoColor = mix(vec3(luma), holoColor, 0.95);

    // Edge glow
    vec3 edges = edgeGlow(uv);
    holoColor += edges * vec3(0.1, 0.6, 1.0) * 1.5;

    // Transparency wave
    float wave = 0.8;
    float wave2 = 0.5;
    holoColor *= wave * wave2;

    // Flicker
    float flicker = 0.92 + 0.08 * sin(t * 0.8) * sin(t * 0.9);
    holoColor *= flicker;

    // Vignette
    vec2 vp = uv - 0.5;
    float vig = 1.0 - smoothstep(0.5, 1.1, length(vp));
    holoColor *= vig;

    // Final contrast
    holoColor = (holoColor - 0.5) * 1.70 + 0.5;

    // Slight gamma correction for brighter highlights
    holoColor = pow(clamp(holoColor, 0.0, 1.0), vec3(1.3));

    gl_FragColor = vec4(clamp(holoColor, 0.0, 1.0), 1.0);
}