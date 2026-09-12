#version 120
// AETHER composite2 — lens glare: threshold + anamorphic-ish blur
#include "/lib/settings.glsl"
#include "/lib/common.glsl"

uniform sampler2D colortex0;
uniform float viewWidth, viewHeight;
varying vec2 texcoord;

// Physically inspired glare: tight kernel + faint horizontal streak,
// instead of one huge gaussian bloom.
void main() {
    vec2 px = 1.0 / vec2(viewWidth, viewHeight);
    vec3 glare = vec3(0.0);
    float wsum = 0.0;

    // small disk (halation) — 25 taps, wider spacing (was 49)
    for (int x = -2; x <= 2; x++)
    for (int y = -2; y <= 2; y++) {
        vec2 o = vec2(x, y) * px * 4.5;
        float w = exp(-dot(vec2(x, y), vec2(x, y)) * 0.35);
        vec3 c = texture2D(colortex0, texcoord + o).rgb;
        float lum = luminance(c);
        // soft knee threshold — only genuinely bright HDR values glare
        c *= smoothstep(1.5, 6.0, lum);
        glare += c * w;
        wsum += w;
    }
    glare /= wsum;

    // horizontal streak (lens flare hint) — 13 taps (was 17)
    vec3 streak = vec3(0.0);
    for (int i = -6; i <= 6; i++) {
        vec2 o = vec2(float(i) * 8.0, 0.0) * px;
        vec3 c = texture2D(colortex0, texcoord + o).rgb;
        c *= smoothstep(4.0, 14.0, luminance(c));
        streak += c * exp(-abs(float(i)) * 0.55);
    }
    streak *= vec3(0.75, 0.85, 1.15) * 0.08; // cool-tinted streak

/* DRAWBUFFERS:3 */
    gl_FragData[0] = vec4(glare + streak, 1.0);
}
