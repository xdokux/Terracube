float acosf(float x) {
    // GPGPU Programming for Games and Science
    float res = -0.156583 * abs(x) + PI / 2.0;
    res *= sqrt(1.0 - abs(x));
    return x >= 0 ? res : PI - res;
}

float rescale(float l, float L, float x) {
    return (x - l) / (L - l);
}
vec2 rescale(float l, float L, vec2 x) {
    return (x - l) / (L - l);
}

float linstep(float l, float L, float x) {
    return clamp(rescale(l, L, x), 0, 1);
}

float len2(vec2 v) {
    return dot(v, v);
}

float len2(vec3 v) {
    return dot(v, v);
}

float min_component(vec2 a) {
    return min(a.x, a.y);
}
float min_component(vec3 a) {
    return min(a.x, min(a.y, a.z));
}
float min_component(vec4 a) {
    return min(a.x, min(a.y, min(a.z, a.w)));
}

float max_component(vec2 a) {
    return max(a.x, a.y);
}
float max_component(vec3 a) {
    return max(a.x, max(a.y, a.z));
}
float max_component(vec4 a) {
    return max(a.x, max(a.y, max(a.z, a.w)));
}

float lerp(float tl, float tr, float bl, float br, vec2 Coords) {
    vec2 f = fract(Coords * resolution);

    float a = mix(tl, tr, f.x);
    float b = mix(bl, br, f.y);
    return mix(a, b, f.y);
}

float pow2(float x) {
    return x * x;
}
float pow4(float x) {
    return pow2(pow2(x));
}
float pow1_5(float x) {
    return x * sqrt(x);
}
vec2 pow2(vec2 x) {
    return x * x;
}
vec2 pow4(vec2 x) {
    return pow2(pow2(x));
}
vec2 pow1_5(vec2 x) {
    return x * sqrt(x);
}
vec3 pow2(vec3 x) {
    return x * x;
}
vec3 pow4(vec3 x) {
    return pow2(pow2(x));
}
vec3 pow1_5(vec3 x) {
    return x * sqrt(x);
}
vec4 pow2(vec4 x) {
    return x * x;
}
vec4 pow4(vec4 x) {
    return pow2(pow2(x));
}
vec4 pow1_5(vec4 x) {
    return x * sqrt(x);
}

float pow1_5_f(float x) {
    return mix(pow2(x), x, sqrt(2) - 1);
}

float pow1_33_f(float x) {
    return mix(pow2(x), x, 0.5911);
}

float len_sq(vec3 x) {
    return max_component(abs(x));
}

float shadow_fade(vec3 PlayerPos, float Dist) {
    return smoothstep(Dist - 16, Dist, len_sq(PlayerPos));
}
