// https://64.github.io/tonemapping/

vec3 reinhard_jodie(vec3 v)
{
    float l = get_luminance(v);
    vec3 tv = v / (1.0f + v);
    return mix(v / (1.0f + l), tv, tv);
}
