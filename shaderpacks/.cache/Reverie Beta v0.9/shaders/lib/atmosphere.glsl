vec3 BETA_R = vec3(5.802e-6, 13.558e-6, 33.1e-6) * betaRfact;
float BETA_M = 3.996e-6 * fogAmount;
float BETA_M_A = BETA_M * 1.101;
const vec3 BETA_O_A = vec3(0.650e-6, 1.881e-6, 0.085e-6);
vec3 BETA_R_E = BETA_R;
float BETA_M_E = BETA_M + BETA_M_A;
const vec3 BETA_O_E = BETA_O_A;

// Atmosphere height
const float EarthRad = 6360e3;
const float AtmRad = 6420e3;

const float Hr = 7994;
const float Hm = 1200;

const float ISOTROPIC_PHASE = 1 / (4 * PI);

float rayleigh_phase(float Mu) {
    return 3 / (16 * PI) * (1 + pow2(Mu));
}

float cs_phase(float Mu, const float g) {
    float g2 = g * g;
    float A = 3 * (1 - g2) * (1 + Mu * Mu);
    float B = 8 * PI * (2 + g2) * pow1_5(1 + g2 - 2 * g * Mu);
    return A / B;
}

float hg_phase(float Mu, float g) {
    float g2 = g*g;
    float A = pow1_5(1 + g2 - 2 * g * Mu);
    return ISOTROPIC_PHASE * (1 - g2) / A;
}

float draine_phase(float Mu, float g, float a) {
    float A = 1 + a * pow2(Mu);
    float B = 1 + a * (1 + 2 * pow2(g)) / 3;
    return A / B * hg_phase(Mu, g);
}

float hg_draine(float Mu, float gMsMul) {
    const float d = 10;
    const float g_hg = exp(-0.0990567 / (d - 1.67154));
    const float g_draine = exp(-2.20679 / (d + 3.91029) - 0.428934);
    const float a = exp(3.62489 - 8.29288 / (d + 5.52825));
    const float w = exp(-0.599085 / (d - 0.641583) - 0.665888);
    return mix(hg_phase(Mu, gMsMul * g_hg), draine_phase(Mu, gMsMul * g_draine, a), w);
}

float hg_draine(float Mu) {
    return hg_draine(Mu, 1);
}

float density_exp(float h, float scale) {
    return exp(-h / scale);
}

float density_ozone(float h) {
    float a = abs(h - 25000) / 15000;
    return max(1 - a, 0);
}

vec3 all_densities(float h) {
    return vec3(
        density_exp(h, Hr),
        density_exp(h, Hm),
        density_ozone(h)
    );
} 

float cs_phase(float Mu) {
    return cs_phase(Mu, anisotropy);
}

vec3 vec_from_ang(float theta) {
    return vec3(sin(theta), cos(theta), 0);
}

vec3 calc_transmittance(vec3 Origin, vec3 Dir, float t1) {
    const float STEP_COUNT = 12;
    float Step = t1 / STEP_COUNT;
    float tCurrent = 0.0;
    vec3 Sum = vec3(0);
    for(int i = 0; i < STEP_COUNT; i++) {
        vec3 P = Origin + (tCurrent + Step * 0.5) * Dir;
        float SunLen = length(P) - EarthRad;
        // if(SunLen < 0) return vec3(0);

        Sum += all_densities(SunLen);
        tCurrent += Step;
    }

    vec3 T = Sum.x * BETA_R_E + Sum.y * BETA_M_E + Sum.z * BETA_O_E;
    return exp(-T * Step);
}

vec3 retrieve_transmittance(float Len, float LdotUp) {
    float x = Len / (AtmRad - EarthRad);
    return texture(atm_transmittance_sampler, vec2(LdotUp * 0.5 + 0.5, x)).rgb;
}

struct ScatteringResult {
    vec3 Transmittance;
    vec3 MultiScatt;
    vec3 L;
};

vec3 calc_scatt_towards_sun(vec3 P, vec3 LightDir, float Len, vec2 Phase, vec3 RayScattering, float MieScattering) {
    // if(LightDir.y < -0.1) return vec3(0);

    // // Earth's shadow
    float _t0s, _t1s;
    bool Hit = raySphereIntersect(P, LightDir, EarthRad, _t0s, _t1s);
    if(_t0s > 0 && Hit) return vec3(0);

    vec3 Pa_PcSun = retrieve_transmittance(Len, dot(LightDir, P / (Len + EarthRad)));
    return (RayScattering * Phase.x + MieScattering * Phase.y) * Pa_PcSun;
}

ScatteringResult calc_atm_scatt(vec3 Origin, vec3 Dir, vec3 SunDir, const int STEP_COUNT, const bool USE_ISOTROPIC_PHASE, const bool USE_MULTI_SCATT) {
    // Calculate intersections
    float _t0, _t1, t0, t1, tmin = 0, tmax = 1e9;
    bool Hit = raySphereIntersect(Origin, Dir, EarthRad, _t0, _t1); 
    if(Hit && _t1 > 0) tmax = max(0, _t0);

    Hit = raySphereIntersect(Origin, Dir, AtmRad, t0, t1);
    if(!Hit || t1 <= 0) {
        ScatteringResult result;
        result.Transmittance = vec3(1);
        result.MultiScatt = vec3(0);
        result.L = vec3(0);
        return result;
    }
    if(t0 > 0) {
        tmin = t0;
    }
    if(t1 < tmax) tmax = t1;

    float Step = (tmax-tmin) / STEP_COUNT;
    float tCurrent = tmin;
    vec3 Throughput = vec3(1);

    ScatteringResult result;
    result.MultiScatt = vec3(0);
    result.L = vec3(0);

    float VdotLSun = dot(Dir, SunDir);
    float VdotLMoon = dot(Dir, -SunDir);
    vec4 Phase = vec4(ISOTROPIC_PHASE);
    if(!USE_ISOTROPIC_PHASE) Phase = vec4(
        rayleigh_phase(VdotLSun),
        cs_phase(VdotLSun),
        rayleigh_phase(VdotLMoon),
        cs_phase(VdotLMoon)
    );

    for(int i = 0; i < STEP_COUNT; i++) {
        vec3 P = Origin + (tCurrent + Step * 0.5) * Dir;
        float Len = length(P) - EarthRad;
        // if(Len < 0) break;

        vec3 OpticalDepth = all_densities(Len) * Step;

        vec3 RayScattering = BETA_R * OpticalDepth.x;
        float MieScattering = BETA_M * OpticalDepth.y;

        vec3 ScatteringSample = vec3(0);
        ScatteringSample += calc_scatt_towards_sun(P, SunDir, Len, Phase.xy, RayScattering, MieScattering) * DayAmbientColor;
        ScatteringSample += calc_scatt_towards_sun(P, -SunDir, Len, Phase.zw, RayScattering, MieScattering) * NightAmbientColor;
        
        vec3 MediumScattering = RayScattering + MieScattering;
        vec3 MediumExtinction = OpticalDepth.x * BETA_R_E + OpticalDepth.y * BETA_M_E + OpticalDepth.z * BETA_O_E;
        vec3 TransmittanceSample = exp(-MediumExtinction);
        
        if(USE_MULTI_SCATT) {
            float u = dot(vec3(0, 1, 0), SunDir) * 0.5 + 0.5;
            float v = (P.y - EarthRad) / (AtmRad - EarthRad);
            ScatteringSample += texture(atm_multi_scattering_sampler, vec2(u, v)).rgb * MediumScattering;
        }

        result.MultiScatt += Throughput * MediumScattering * (1 - TransmittanceSample) / MediumExtinction;
        result.L += Throughput * ScatteringSample * (1 - TransmittanceSample) / MediumExtinction;

        Throughput *= TransmittanceSample;
        tCurrent += Step;
    }

    result.Transmittance = Throughput;

    return result;
}

float height_falloff(float Height, const float MAX_HEIGHT) {
    return 1 - linstep(MAX_HEIGHT - 100, MAX_HEIGHT, Height);
}

vec3 get_direct_color(const bool IsMoon, float Len) {
    #ifdef DIMENSION_END
        return vec3(1);
    #endif

    vec3 LightPosN = IsMoon ? -sunPosN : sunPosN;

    float mu = dot(gbufferModelView[1].xyz, LightPosN);

    vec3 SkyColor = retrieve_transmittance(Len, mu);

    // SkyColor *= 1 - rainStrength * 0.5 - thunderStrength * 0.4;

    if (!IsMoon)
        return SkyColor * SunColor;
    else
        return SkyColor * MoonColor;
}

vec3 get_shadowlight_color() {
    vec3 LightColorDirect;
    if (sunAngle < 0.5)
        LightColorDirect = dataBuf.SunColor;
    else
        LightColorDirect = dataBuf.MoonColor;

    float LHeight = sin(sunAngle * TAU); // to_player_pos(sunPosN).y;
    LightColorDirect *= smoothstep(0.0, 0.05, abs(LHeight));
    return LightColorDirect;
}

vec3 get_ambient_color() {
    #ifndef DIMENSION_OVERWORLD
    return vec3(0);
    #endif
    const float STEP_COUNT = 6.0;
    vec3 Ambient = vec3(0);
    for (float i = 0.0; i < STEP_COUNT; i++) {
        float VangUp = (i / STEP_COUNT - 0.5) * PI / 2; // [0, PI / 2]
        float v = 0.5 + 0.5 * sign(-VangUp) * sqrt(abs(-VangUp) / (PI / 2)); // [0.5, 1]
        Ambient += texture_rgbm(atm_skyview_sampler, vec2(0.5, v)).rgb;
    }
    return Ambient / STEP_COUNT;
}
