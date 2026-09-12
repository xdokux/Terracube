// AETHER — shared math, color science, atmosphere
#ifndef COMMON_GLSL
#define COMMON_GLSL

#define PI 3.14159265359

float luminance(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

vec3 srgbToLinear(vec3 c) { return pow(c, vec3(2.2)); }
vec3 linearToSrgb(vec3 c) { return pow(max(c, 0.0), vec3(1.0 / 2.2)); }

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}
float hash13(vec3 p3) {
    p3 = fract(p3 * 0.1031);
    p3 += dot(p3, p3.zyx + 31.32);
    return fract((p3.x + p3.y) * p3.z);
}
float noise3(vec3 x) {
    vec3 i = floor(x), f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash13(i + vec3(0,0,0)), hash13(i + vec3(1,0,0)), f.x),
                   mix(hash13(i + vec3(0,1,0)), hash13(i + vec3(1,1,0)), f.x), f.y),
               mix(mix(hash13(i + vec3(0,0,1)), hash13(i + vec3(1,0,1)), f.x),
                   mix(hash13(i + vec3(0,1,1)), hash13(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float fbm(vec3 p) {
    float a = 0.5, s = 0.0;
    for (int i = 0; i < 4; i++) { s += a * noise3(p); p *= 2.17; a *= 0.5; }
    return s;
}

// Interleaved gradient noise — stable per-pixel dither
float ign(vec2 px) {
    return fract(52.9829189 * fract(dot(px, vec2(0.06711056, 0.00583715))));
}

// ---------------- AgX tonemapping ----------------
vec3 agxDefaultContrastApprox(vec3 x) {
    vec3 x2 = x * x;
    vec3 x4 = x2 * x2;
    return + 15.5     * x4 * x2
           - 40.14    * x4 * x
           + 31.96    * x4
           - 6.868    * x2 * x
           + 0.4298   * x2
           + 0.1191   * x
           - 0.00232;
}
vec3 agx(vec3 val) {
    const mat3 agx_mat = mat3(
        0.842479062253094,  0.0423282422610123, 0.0423756549057051,
        0.0784335999999992, 0.878468636469772,  0.0784336,
        0.0792237451477643, 0.0791661274605434, 0.879142973793104);
    const float min_ev = -12.47393, max_ev = 4.026069;
    val = agx_mat * val;
    val = clamp(log2(val), min_ev, max_ev);
    val = (val - min_ev) / (max_ev - min_ev);
    return agxDefaultContrastApprox(val);
}
vec3 agxEotf(vec3 val) {
    const mat3 agx_mat_inv = mat3(
         1.19687900512017,   -0.0528968517574562, -0.0529716355144438,
        -0.0980208811401368,  1.15190312990417,   -0.0980434501171241,
        -0.0990297440797205, -0.0989611768448433,  1.15107367264116);
    return pow(max(agx_mat_inv * val, 0.0), vec3(2.2));
}
vec3 agxLook(vec3 val) {
    // Aether look: gentle punch, filmic saturation
    float lum = luminance(val);
    vec3 offset = vec3(0.0);
    vec3 slope  = vec3(1.02, 1.0, 0.99);
    vec3 power  = vec3(1.12);
    float sat   = 1.12;
    val = pow(val * slope + offset, power);
    return lum + sat * (val - lum);
}
vec3 tonemapAgX(vec3 hdr) { return agxEotf(agxLook(agx(hdr))); }

// ---------------- Atmosphere (analytic single-scatter) ----------------
const vec3 RAYLEIGH_BETA = vec3(5.8e-3, 13.5e-3, 33.1e-3); // per unit, tuned
const float MIE_BETA_BASE = 4.0e-3;

float phaseRayleigh(float mu) { return 3.0 / (16.0 * PI) * (1.0 + mu * mu); }
float phaseMie(float mu, float g) {
    float g2 = g * g;
    return (1.0 - g2) / (4.0 * PI * pow(1.0 + g2 - 2.0 * g * mu, 1.5));
}

// Optical depth toward the sky for a ray at elevation `mu = dir.y`
float airMass(float y) {
    return 1.0 / max(y * 0.9 + 0.12, 0.02);
}

// hazeAmt: humidity/weather-driven mie multiplier
vec3 skyScatter(vec3 dir, vec3 sunDir, float hazeAmt, out vec3 transmittance) {
    float mu = dot(dir, sunDir);
    float mass = airMass(dir.y) * SKY_DENSITY;
    float sunMass = airMass(max(sunDir.y, -0.05));

    vec3 mieBeta = vec3(MIE_BETA_BASE) * (1.0 + hazeAmt * 3.0);
    vec3 extinct = RAYLEIGH_BETA + mieBeta * 1.11;

    transmittance = exp(-extinct * mass * 18.0);
    // Sunlight surviving to the scattering point (drives sunset reddening)
    vec3 sunTrans = exp(-extinct * sunMass * 14.0);

    vec3 scatter = (RAYLEIGH_BETA * phaseRayleigh(mu)
                  + mieBeta * phaseMie(mu, 0.76 - hazeAmt * 0.15))
                  / max(extinct, vec3(1e-5));

    vec3 sky = scatter * sunTrans * (1.0 - transmittance) * 22.0;

    // Multiple-scatter floor keeps the zenith from going black
    sky += vec3(0.15, 0.26, 0.45) * sunTrans * 0.12 * (1.0 - hazeAmt * 0.4);
    return sky;
}

// Sunlight color after atmospheric extinction (for direct lighting)
vec3 sunColor(vec3 sunDir, float hazeAmt) {
    float sunMass = airMass(max(sunDir.y, 0.0));
    vec3 mieBeta = vec3(MIE_BETA_BASE) * (1.0 + hazeAmt * 3.0);
    vec3 extinct = RAYLEIGH_BETA + mieBeta * 1.11;
    return exp(-extinct * sunMass * 14.0) * smoothstep(-0.06, 0.08, sunDir.y);
}

#endif
