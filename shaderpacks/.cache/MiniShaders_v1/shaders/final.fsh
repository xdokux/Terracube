#version 120

// GamesofDev is non chalant
varying vec2 texcoord;

uniform sampler2D colortex0;
uniform float viewWidth;
uniform float viewHeight;

// Quality setting
#ifndef QUALITY
  #define QUALITY 2
#endif

// Post-processing settings defaults
#ifndef SATURATION
  #define SATURATION 1.9
#endif
#ifndef EXPOSURE
  #define EXPOSURE 1.15
#endif
#ifndef BRIGHTNESS
  #define BRIGHTNESS 1.0
#endif

// ACES tone mapping
vec3 ACESFilm(vec3 x) {
    float a = 2.51;
    float b = 0.03;
    float c = 2.43;
    float d = 0.59;
    float e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

// Simple Reinhard tonemapping (for Min quality)
vec3 ReinhardTonemap(vec3 x) {
    return x / (x + vec3(1.0));
}

void main() {
    vec3 color = texture2D(colortex0, texcoord).rgb;
    
#if QUALITY == 1
    // ═══════════════════════════════════════════════════════════════════
    // MINIMUM — no bloom, simple tonemapping, no vignette
    // ═══════════════════════════════════════════════════════════════════
    
    color *= 0.85;
    color = ReinhardTonemap(color);
    color = pow(color, vec3(1.0 / 2.2));

#elif QUALITY == 3
    // ═══════════════════════════════════════════════════════════════════
    // ULTRA — full bloom, ACES, color grading, vignette, saturation
    // ═══════════════════════════════════════════════════════════════════
    
    // High-quality 13-tap bloom
    vec2 texelSize = vec2(1.0 / viewWidth, 1.0 / viewHeight);
    vec3 bloom = vec3(0.0);
    float totalWeight = 0.0;
    
    // 13-tap Gaussian-like kernel (cross + diagonals)
    // Center
    bloom += texture2D(colortex0, texcoord).rgb * 4.0;
    totalWeight += 4.0;
    
    // Cross (4 samples)
    bloom += texture2D(colortex0, texcoord + vec2( 1.0, 0.0) * texelSize * 2.0).rgb * 2.0;
    bloom += texture2D(colortex0, texcoord + vec2(-1.0, 0.0) * texelSize * 2.0).rgb * 2.0;
    bloom += texture2D(colortex0, texcoord + vec2( 0.0, 1.0) * texelSize * 2.0).rgb * 2.0;
    bloom += texture2D(colortex0, texcoord + vec2( 0.0,-1.0) * texelSize * 2.0).rgb * 2.0;
    totalWeight += 8.0;
    
    // Diagonals (4 samples)
    bloom += texture2D(colortex0, texcoord + vec2( 1.0, 1.0) * texelSize * 2.0).rgb * 1.0;
    bloom += texture2D(colortex0, texcoord + vec2(-1.0, 1.0) * texelSize * 2.0).rgb * 1.0;
    bloom += texture2D(colortex0, texcoord + vec2( 1.0,-1.0) * texelSize * 2.0).rgb * 1.0;
    bloom += texture2D(colortex0, texcoord + vec2(-1.0,-1.0) * texelSize * 2.0).rgb * 1.0;
    totalWeight += 4.0;
    
    // Wide samples (4 samples) — для более широкого glow
    bloom += texture2D(colortex0, texcoord + vec2( 2.0, 0.0) * texelSize * 4.0).rgb * 0.5;
    bloom += texture2D(colortex0, texcoord + vec2(-2.0, 0.0) * texelSize * 4.0).rgb * 0.5;
    bloom += texture2D(colortex0, texcoord + vec2( 0.0, 2.0) * texelSize * 4.0).rgb * 0.5;
    bloom += texture2D(colortex0, texcoord + vec2( 0.0,-2.0) * texelSize * 4.0).rgb * 0.5;
    totalWeight += 2.0;
    
    bloom /= totalWeight;
    
    // Extract bright parts for bloom contribution
    float bloomBrightness = max(bloom.r, max(bloom.g, bloom.b));
    vec3 bloomContrib = bloom * smoothstep(0.3, 1.0, bloomBrightness);
    
    // Mix bloom with scene
    color = color + bloomContrib * 0.35;
    
    // Exposure — significantly boosted to prevent particles from being black
    color *= EXPOSURE;
    
    // Brightness adjustment
    color *= BRIGHTNESS;
    
    // Add brightness floor for particles and dark areas
    color = max(color, vec3(0.05));
    
    // ACES tone mapping
    color = ACESFilm(color);
    
    // Gamma correction
    color = pow(color, vec3(1.0 / 2.2));
    
    // Enhanced color grading — balanced warm tone
    float luminance = dot(color, vec3(0.2126, 0.7152, 0.0722));
    vec3 warmShift = vec3(1.1, 1.04, 0.9); // softer warm highlights
    vec3 shadowShift = vec3(1.0, 0.98, 0.96); // minimal shift on shadows to preserve particles
    vec3 grading = mix(shadowShift, warmShift, luminance);
    color *= grading;
    
    // Boost midtones for more color pop
    color = pow(color, vec3(0.95));
    
    // Saturation boost (configurable)
    vec3 grey = vec3(luminance);
    color = mix(grey, color, SATURATION);
    
    // Vignette (stronger on Ultra)
    vec2 center = texcoord - 0.5;
    float vignette = 1.0 - dot(center, center) * 0.4;
    color *= vignette;

#else
    // ═══════════════════════════════════════════════════════════════════
    // MEDIUM — light bloom, ACES, light vignette, slight saturation
    // ═══════════════════════════════════════════════════════════════════
    
    // 5-tap bloom (fast)
    vec2 texelSize = vec2(1.0 / viewWidth, 1.0 / viewHeight);
    vec3 bloom = color * 2.0;
    bloom += texture2D(colortex0, texcoord + vec2( 1.5, 0.0) * texelSize).rgb;
    bloom += texture2D(colortex0, texcoord + vec2(-1.5, 0.0) * texelSize).rgb;
    bloom += texture2D(colortex0, texcoord + vec2( 0.0, 1.5) * texelSize).rgb;
    bloom += texture2D(colortex0, texcoord + vec2( 0.0,-1.5) * texelSize).rgb;
    bloom /= 6.0;
    
    float bloomBrightness = max(bloom.r, max(bloom.g, bloom.b));
    vec3 bloomContrib = bloom * smoothstep(0.4, 1.2, bloomBrightness);
    
    color = color + bloomContrib * 0.15;
    
    // Exposure — enhanced to keep particles visible
    color *= EXPOSURE * 0.87;
    
    // Brightness adjustment
    color *= BRIGHTNESS;
    
    // Add brightness floor for particles
    color = max(color, vec3(0.03));
    
    // ACES tone mapping
    color = ACESFilm(color);
    
    // Gamma correction
    color = pow(color, vec3(1.0 / 2.2));
    
    // Enhanced color grading for medium quality — balanced warm
    float luminance = dot(color, vec3(0.2126, 0.7152, 0.0722));
    vec3 warmShift = vec3(1.06, 1.02, 0.94); // soft highlights
    vec3 shadowShift = vec3(1.0, 0.98, 0.97); // minimal shadow shift
    vec3 grading = mix(shadowShift, warmShift, luminance);
    color *= grading;
    
    // Boost midtones
    color = pow(color, vec3(0.96));
    
    // Saturation boost (configurable)
    vec3 grey = vec3(luminance);
    color = mix(grey, color, SATURATION * 0.95);
    
    // Light vignette
    vec2 center = texcoord - 0.5;
    float vignette = 1.0 - dot(center, center) * 0.25;
    color *= vignette;

#endif
    
    gl_FragColor = vec4(color, 1.0);
}
