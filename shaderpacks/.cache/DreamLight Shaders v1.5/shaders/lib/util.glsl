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
    p = p * 2 - 1;
    if (IsDH)
        return project_and_divide(dhProjectionInverse, p);
    else
        return project_and_divide(gbufferProjectionInverse, p);
}

vec3 view_screen(vec3 x, bool IsDH) {
    if (IsDH)
        x = project_and_divide(dhProjection, x);
    else
        x = project_and_divide(gbufferProjection, x);
    x = x * 0.5 + 0.5;
    return x;
}

vec3 to_player_pos(vec3 p) {
    return mat3(gbufferModelViewInverse) * p;
}

vec3 player_view(vec3 p) {
    return mat3(gbufferModelView) * p;
}

float linearize_depth(float D) {
    return near / (1 - D);
}

float ld_exact(float depth, float near, float far) {
    return (near * far) / (depth * (near - far) + far);
}

float ld_exact(float depth, bool IsDH) {
    if (!IsDH)
        return (near * far) / (depth * (near - far) + far);
    else
        return (dhNearPlane * dhFarPlane) / (depth * (dhNearPlane - dhFarPlane) + dhFarPlane);
}

// Creates a TBN matrix from a normal and a tangent
mat3 tbnNormalTangent(vec3 normal, vec3 tangent) {
    // For DirectX normal mapping you want to switch the order of these
    vec3 bitangent = cross(normal, tangent);
    return mat3(tangent, bitangent, normal);
}

// Creates a TBN matrix from just a normal
// The tangent version is needed for normal mapping because
//   of face rotation
mat3 tbnNormal(vec3 normal) {
    // This could be
    // normalize(vec3(normal.y - normal.z, -normal.x, normal.x))
    vec3 tangent = normalize(cross(normal, vec3(0, 1, 1)));
    return tbnNormalTangent(normal, tangent);
}

float get_luminance(vec3 Color) {
    return 0.299 * Color.r + 0.587 * Color.g + 0.114 * Color.b;
}

float get_depth(vec2 ScreenPos, out bool IsDH) {
    float Depth = texture2D(depthtex0, ScreenPos).x;
    IsDH = false;
    #ifdef DISTANT_HORIZONS
    if (Depth >= 1) {
        Depth = texture2D(dhDepthTex, ScreenPos).x;
        IsDH = true;
    }
    #endif
    return Depth;
}

float get_depth_solid(vec2 ScreenPos, out bool IsDH) {
    float Depth = texture2D(depthtex1, ScreenPos).x;
    IsDH = false;
    #ifdef DISTANT_HORIZONS
    if (Depth >= 1) {
        Depth = texture2D(dhDepthTex1, ScreenPos).x;
        IsDH = true;
    }
    #endif
    return Depth;
}

vec2 rotate(vec2 P, float Ang) {
    float cosT = cos(Ang);
    float sinT = sin(Ang);
    return vec2(
        P.x * cosT - P.y * sinT,
        P.y * cosT + P.x * sinT
    );
}

float len2(vec2 v) {
    return dot(v, v);
}

float len2(vec3 v) {
    return dot(v, v);
}

float pow2(float x) {
    return x * x;
}

float pow4(float x) {
    return pow2(pow2(x));
}

vec2 pow2(vec2 x) {
    return x * x;
}

vec2 pow4(vec2 x) {
    return pow2(pow2(x));
}

vec3 pow2(vec3 x) {
    return x * x;
}

vec3 pow4(vec3 x) {
    return pow2(pow2(x));
}

vec4 pow2(vec4 x) {
    return x * x;
}

vec4 pow4(vec4 x) {
    return pow2(pow2(x));
}
