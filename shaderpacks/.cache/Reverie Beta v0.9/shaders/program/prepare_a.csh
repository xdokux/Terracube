#include "/lib/all_the_libs.glsl"

const ivec3 workGroups = ivec3(32, 8, 1);

layout(local_size_x = 8, local_size_y = 8) in;

void main() {
    vec2 FragCoord = gl_GlobalInvocationID.xy;

    float v = FragCoord.x / 256;
    float x = FragCoord.y / 64;

    float Height = EarthRad + x * (AtmRad - EarthRad) + 1;
    vec3 Origin = vec3(0, Height, 0);
    float thetaS = acosf((v - 0.5) * 2);
    vec3 Dir = vec_from_ang(thetaS);

    float _t0, _t1;
    raySphereIntersect(Origin, Dir, AtmRad, _t0, _t1);

    vec3 Transmittance = calc_transmittance(Origin, Dir, _t1);

    imageStore(atm_transmittance, ivec2(FragCoord), vec4(Transmittance, 0));
}