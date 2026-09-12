vec3 schlick(vec3 N, vec3 V, vec3 F0) {
    float cosTheta = clamp(dot(N, V), 0, 1);
    return F0 + (1 - F0) * pow(1 - cosTheta, 5);
}

// https://www.researchgate.net/publication/221546550_Fresnel_Term_Approximations_for_Metals
// vec3 fresnel_metals(vec3 N, vec3 V, mat2x3 Metal) {
//     vec3 n = Metal[0];
//     vec3 k = Metal[1];
//     float cosTheta = clamp(dot(N, V), 0, 1);
//     vec3 k2 = k * k;
//     vec3 A = pow2(n - 1) + 4 * n * pow(1 - cosTheta, 5) + k2;
//     vec3 B = pow2(n + 1) + k2;
//     return A / B;
// }
vec3 fresnel_metals(vec3 N, vec3 V, mat2x3 F) {
    const float thetaM = 1.425934;
    const float cosThetaM = cos(thetaM);

    vec3 a = (F[0] + (1 - F[0]) * pow(1 - cosThetaM, 5) - F[1]) / (cosThetaM * pow(1 - cosThetaM, 6));

    float cosTheta = clamp(dot(N, V), 0, 1);

    a = clamp(a, 0, 1);

    return F[0] + (1 - F[0]) * pow(1 - cosTheta, 5) - a * cosTheta * pow(1 - cosTheta, 6);
}

float DistributionGGX(vec3 N, vec3 H, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    float NdotH = max(dot(N, H), 0.0);
    float NdotH2 = NdotH * NdotH;

    float num = a2;
    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    denom = PI * denom * denom;

    return num / denom;
}

float GeometrySchlickGGX(float NdotV, float roughness) {
    float r = (roughness + 1.0);
    float k = (r * r) / 8.0;

    float num = NdotV;
    float denom = NdotV * (1.0 - k) + k;

    return num / denom;
}
float GeometrySmith(vec3 N, vec3 V, vec3 L, float roughness) {
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    float ggx2 = GeometrySchlickGGX(NdotV, roughness);
    float ggx1 = GeometrySchlickGGX(NdotL, roughness);

    return ggx1 * ggx2;
}

vec3 cook_torrance(vec3 V, vec3 LightDir, vec3 Normal, float Roughness, vec3 H, vec3 F) {
    float D = DistributionGGX(Normal, H, Roughness);
    float G = GeometrySmith(Normal, V, LightDir, Roughness);
    vec3 Final = (D * F * G) / (4 * max(dot(V, Normal), 0) * max(dot(Normal, LightDir), 0) + 0.001);
    return min(Final, vec3(50));
}
