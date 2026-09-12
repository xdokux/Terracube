#include "/lib/all_the_libs.glsl"

#ifndef DIMENSION_OVERWORLD
const ivec3 workGroups = ivec3(0, 0, 0);
#else
const ivec3 workGroups = ivec3(1, 1, 1);
#endif
layout(local_size_x = 16, local_size_y = 16) in;

// Declaring as vec3 doesn't seem to work???
shared float L_x[16][16], L_y[16][16], L_z[16][16];
vec3 get_L(int i, int j) { return vec3(L_x[i][j], L_y[i][j], L_z[i][j]); }
void set_L(int i, int j, vec3 val) { L_x[i][j] = val.x; L_y[i][j] = val.y; L_z[i][j] = val.z; }

const float STEP_COUNT = 16;

vec3 fibonacciSphereSample(float i, const float N) {
    float phi = acosf(1.0 - 2.0 * (i + 0.5) / N);   // polar angle
    const float PHI = (1 + sqrt(5)) / 2;
    float theta = TAU * i / PHI;      // azimuthal angle

    return vec3(
        sin(phi) * cos(theta),
        sin(phi) * sin(theta),
        cos(phi)
    );
}


void gather(float i) {
    vec3 L = vec3(0);
    vec3 Origin = vec3(0, EarthRad + 300, 0);
    
    
    vec3 Dir = fibonacciSphereSample(i, pow2(STEP_COUNT));
    
    ScatteringResult result = calc_atm_scatt(Origin, Dir, view_player(sunPosN, false), 16, false, true);
    set_L(int(gl_GlobalInvocationID.x), int(gl_GlobalInvocationID.y), result.L);
}

void main() {
    int d = int(16 * gl_GlobalInvocationID.x + gl_GlobalInvocationID.y);
    gather(d);

    barrier();

    vec2 FragCoord = gl_GlobalInvocationID.xy;
    float VangL = acosf(FragCoord.x / 16 * 2 - 1);
    float VangUp = acosf(FragCoord.y / 16 * 2 - 1);
    vec3 Normal = normalize(vec3(cos(VangL), -cos(VangUp), sin(VangL)));

    vec3 FinalColor = vec3(0);
    for(int i = 0; i < 16; i++) {
        for(int j = 0; j < 16; j++) {
            
            int df = 16 * i + j;
            vec3 LightIncDir = fibonacciSphereSample(df, pow2(STEP_COUNT));

            float F = max(0, dot(Normal, -LightIncDir));
            FinalColor += get_L(i, j) * F;
        }
    }
    FinalColor = FinalColor / pow2(STEP_COUNT);

    // We multiply by 4 here because that's how many days I already
    // wasted trying to get this to work
    FinalColor *= 4;

    imageStore(image0, ivec2(FragCoord), vec4(FinalColor, 0));

}