#extension GL_EXT_gpu_shader4 : enable
float random(vec2 coords) {
    return fract(sin(dot(coords.xy, vec2(12.9898, 78.233))) * 43758.5453);
}
float random3D(vec3 p) {
    return fract(sin(dot(p, vec3(12.9898, 78.233, 45.543))) * 43758.5453);
}
vec3 project_and_divide(mat4 Projection_mat, vec3 x) {
    vec4 HomogeneousPos = Projection_mat * vec4(x, 1);
    return HomogeneousPos.xyz / HomogeneousPos.w;
}
vec3 to_view_pos(vec3 p, bool IsDH) {
    p = p * 2.0 - 1.0;
    return project_and_divide(IsDH ? dhProjectionInverse : gbufferProjectionInverse, p);
}
vec3 view_screen(vec3 x, bool IsDH) {
    return project_and_divide(IsDH ? dhProjection : gbufferProjection, x) * 0.5 + 0.5;
}
vec3 to_player_pos(vec3 p) {
    return mat3(gbufferModelViewInverse) * p;
}
vec3 player_view(vec3 p) {
    return mat3(gbufferModelView) * p;
}
float linearize_depth(float D) {
    return near / (1.0 - D);
}
float ld_exact(float depth, float near, float far) {
    return (near * far) / (depth * (near - far) + far);
}
mat3 tbnNormalTangent(vec3 normal, vec3 tangent) {
    vec3 bitangent = cross(normal, tangent);
    return mat3(tangent, bitangent, normal);
}
mat3 tbnNormal(vec3 normal) {
    vec3 reference = abs(normal.y) < 0.999 ? vec3(0, 1, 0) : vec3(1, 0, 0);
    vec3 tangent = normalize(cross(reference, normal));
    return tbnNormalTangent(normal, tangent);
}
float get_luminance(vec3 Color) {
    return dot(Color, vec3(0.299, 0.587, 0.114));
}
bool isDH_pixel(vec2 screenCoord) {
    #ifdef DISTANT_HORIZONS
    float vanillaDepth = texture(depthtex0, screenCoord).r;
    float dhDepth = texture(dhDepthTex, screenCoord).r;
    return (vanillaDepth >= 1.0 && dhDepth < 1.0);
    #else
    return false;
    #endif
}
vec2 rotate(vec2 P, float Ang) {
    float cosT = cos(Ang);
    float sinT = sin(Ang);
    return vec2(P.x * cosT - P.y * sinT, P.x * sinT + P.y * cosT);
}
float len2(vec2 v) { return dot(v, v); }
float len2(vec3 v) { return dot(v, v); }
float pow2(float x) { return x * x; }
float pow4(float x) {
    x *= x;
    return x * x;
}
vec2 pow2(vec2 x) { return x * x; }
vec3 pow2(vec3 x) { return x * x; }
vec4 pow2(vec4 x) { return x * x; }
vec2 pow4(vec2 x) {
    x *= x;
    return x * x;
}
vec3 pow4(vec3 x) {
    x *= x;
    return x * x;
}
vec4 pow4(vec4 x) {
    x *= x;
    return x * x;
}
float min_component(vec2 a) { return min(a.x, a.y); }
float min_component(vec3 a) { return min(min(a.x, a.y), a.z); }
float min_component(vec4 a) { return min(min(a.x, a.y), min(a.z, a.w)); }
float max_component(vec2 a) { return max(a.x, a.y); }
float max_component(vec3 a) { return max(max(a.x, a.y), a.z); }
float max_component(vec4 a) { return max(max(a.x, a.y), max(a.z, a.w)); }
float cs_phase(float Mu, float g) {
    float g2 = g * g;
    float denom = pow(1.0 + g2 - 2.0 * g * Mu, 1.5);
    return (3.0 * (1.0 - g2) * (1.0 + Mu * Mu)) / (8.0 * 3.14159 * (2.0 + g2) * denom);
}
float xlf_phase(float angle, const float g) {
    float g2 = g * g;
    float denom = 1.0 + g2 - 2.0 * g * angle;
    return 0.0795774715 * (1.5 * (1.0 - g2) / (2.0 + g2)) * ((1.0 + angle * angle) / denom + g * angle);
}
