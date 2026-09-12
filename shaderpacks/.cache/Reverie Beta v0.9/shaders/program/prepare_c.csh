#include "/lib/all_the_libs.glsl"

const ivec3 workGroups = ivec3(16, 8, 1);

layout(local_size_x = 8, local_size_y = 8) in;

void main() {
    vec2 FragCoord = gl_GlobalInvocationID.xy;

    float u = FragCoord.x / 128;
    float v = FragCoord.y / 64;

    float Height = EarthRad + max(1, cameraPosition.y * 5);

    vec3 Origin = vec3(0, Height, 0);

    float VangL = acosf(u * 2 - 1);
    float VangUp = v > 0.5 ? TAU*pow2(v)-TAU*v+PI : -TAU*pow2(v)+TAU*v;
    vec3 Dir = vec3(
        sin(VangUp) * cos(VangL),
        -cos(VangUp),
        sin(VangUp) * sin(VangL)
    );

    float LdotU = view_player(sunPosN, false).y;
    vec3 SunDir = vec3(sqrt(1 - pow2(LdotU)), LdotU, 0);

    vec3 Scattering = calc_atm_scatt(Origin, Dir, SunDir, 32, false, true).L;
    imageStore(atm_skyview, ivec2(FragCoord), RGBMEncode(Scattering));
}