#version 120
// AETHER final — AgX display transform, lens effects, grain
#include "/lib/settings.glsl"
#include "/lib/common.glsl"

uniform sampler2D colortex0;
uniform sampler2D colortex3;   // glare
uniform sampler2D colortex4;   // exposure
uniform float frameTimeCounter;
uniform float viewWidth, viewHeight;

varying vec2 texcoord;

void main() {
    vec4 expData = texture2D(colortex4, vec2(0.5));
    float exposure = max(expData.r, 1e-4);

    // Lens breathing: tiny FOV shift while exposure is transitioning
    float breathing = clamp((expData.g - expData.r) / max(expData.r, 1e-3), -1.0, 1.0);
    vec2 uv = (texcoord - 0.5) * (1.0 - breathing * 0.004) + 0.5;

    // Chromatic aberration, growing toward screen edges
    vec2 fromCenter = uv - 0.5;
    float edge = dot(fromCenter, fromCenter) * 2.0;
    vec2 caShift = fromCenter * edge * 0.006 * CHROM_ABERRATION;
    vec3 hdr;
    hdr.r = texture2D(colortex0, uv + caShift).r;
    hdr.g = texture2D(colortex0, uv).g;
    hdr.b = texture2D(colortex0, uv - caShift).b;

    // Lens glare (kept subtle — highlights bleed, scene stays crisp)
    vec3 glare = texture2D(colortex3, uv).rgb;
    hdr += glare * GLARE_STRENGTH * 0.35;

    // Exposure then AgX
    hdr *= exposure;
    vec3 color = tonemapAgX(hdr);

    // Film grain — luminance-dependent, finer in bright areas
    float grain = (hash12(gl_FragCoord.xy + fract(frameTimeCounter) * 1000.0) - 0.5);
    color += grain * FILM_GRAIN * (1.0 - luminance(color) * 0.7);

    // Gentle cinematic edge falloff (not a hard vignette)
    color *= 1.0 - edge * 0.06;

    gl_FragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
