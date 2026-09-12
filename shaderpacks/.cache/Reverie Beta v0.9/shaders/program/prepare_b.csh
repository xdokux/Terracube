#include "/lib/all_the_libs.glsl"

const ivec3 workGroups = ivec3(32, 32, 1);

layout(local_size_x = 64, local_size_y = 1) in;

// Declaring as vec3 doesn't seem to work???
shared float L2_x[64], L2_y[64], L2_z[64];
shared float fms_x[64], fms_y[64], fms_z[64];
vec3 get_L2(int i) { return vec3(L2_x[i], L2_y[i], L2_z[i]); }
vec3 get_fms(int i) { return vec3(fms_x[i], fms_y[i], fms_z[i]); }
void set_L2(int i, vec3 val) { L2_x[i] = val.x; L2_y[i] = val.y; L2_z[i] = val.z; }
void set_fms(int i, vec3 val) { fms_x[i] = val.x; fms_y[i] = val.y; fms_z[i] = val.z; }

const float STEP_COUNT = 64;

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


void gather(vec3 P, vec3 SunDir) {
    vec3 L2 = vec3(0);
    vec3 fms = vec3(0);
    
    int i = int(gl_LocalInvocationID.x);
    vec3 Dir = fibonacciSphereSample(i, STEP_COUNT);
    
    ScatteringResult result = calc_atm_scatt(P, Dir, SunDir, 16, true, false);
    set_L2(i, result.L);
    set_fms(i, result.MultiScatt);
}

void main() {
    vec2 FragCoord = gl_WorkGroupID.xy;

    float u = FragCoord.x / 32;
    float v = FragCoord.y / 32;

    float thetaS = acosf(u * 2 - 1);
    float Height = EarthRad + v * (AtmRad - EarthRad) + 1;

    vec3 Origin = vec3(0, Height, 0);
    vec3 SunDir = vec_from_ang(thetaS);

    gather(Origin, SunDir);

    barrier();

    int i = int(gl_LocalInvocationID.x);

    if(i < 32) {
        set_L2(i, get_L2(i) + get_L2(i + 32));
        set_fms(i, get_fms(i) + get_fms(i + 32));
    }
    barrier();
    if(i < 16) {
        set_L2(i, get_L2(i) + get_L2(i + 16));
        set_fms(i, get_fms(i) + get_fms(i + 16));
    }
    barrier();
    if(i < 8) {
        set_L2(i, get_L2(i) + get_L2(i + 8));
        set_fms(i, get_fms(i) + get_fms(i + 8));
    }
    barrier();
    if(i < 4) {
        set_L2(i, get_L2(i) + get_L2(i + 4));
        set_fms(i, get_fms(i) + get_fms(i + 4));
    }
    barrier();
    if(i < 2) {
        set_L2(i, get_L2(i) + get_L2(i + 2));
        set_fms(i, get_fms(i) + get_fms(i + 2));
    }
    barrier();

    if(i < 1) {
        set_L2(i, get_L2(i) + get_L2(i + 1));
        set_fms(i, get_fms(i) + get_fms(i + 1));

        vec3 L2 = get_L2(i) / STEP_COUNT;
        vec3 fms = get_fms(i) / STEP_COUNT;

        vec3 MultiScattering = L2 / (1 - fms);

        imageStore(atm_multi_scattering, ivec2(FragCoord), vec4(MultiScattering, 0));
    }
}