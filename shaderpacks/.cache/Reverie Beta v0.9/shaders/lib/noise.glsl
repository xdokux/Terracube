float noise_clouds_base_simple(vec3 p) {
    #ifdef SCREENSHOT_MODE
        vec2 Wind = vec2(0);
    #else
        vec2 Wind = windDirection * frameTimeCounter * 5 + cloudStartOffset;
    #endif
    float Base = texture(cloudNoise, (p.xz + Wind) * 0.0004).r;
    Base = pow(Base, cloudCoverageVl);
    return Base;
}


float noise_clouds_base_simple_flat(vec3 p) {
    #ifdef SCREENSHOT_MODE
        vec2 Wind = vec2(0);
    #else
        vec2 Wind = windDirection * frameTimeCounter * 5 + cloudStartOffset;
    #endif
    float Base = texture(cloudNoise, (p.xz + Wind) * 0.0003).r;
    Base = pow(Base, cloudCoverageFlat);
    return Base;
}

float noise_clouds_flat(vec3 p) {
    float Base = noise_clouds_base_simple_flat(p * 0.5);

    #ifdef SCREENSHOT_MODE
        vec2 Wind = vec2(0);
    #else
        vec2 Wind = windDirection * frameTimeCounter * 5;
    #endif

    vec2 D = textureNice(noisetex, (p.xz + Wind) * 0.000004).rg;
    vec2 Displacement = D * 0.33;

    float Detail = texture(cloudNoise, p.xz * 0.001 + Displacement).r;
    Detail = pow(Detail, cloudCoverageVl);

    return Base * Detail;
}

float noise_clouds_base(vec3 p) {
    #ifdef SCREENSHOT_MODE
        vec2 Wind = vec2(0);
    #else
        vec2 Wind = windDirection * frameTimeCounter * 5 + cloudStartOffset;
    #endif

    float Alt = linstep(CLOUD_LOWER_PLANE, CLOUD_UPPER_PLANE, p.y);
    float HeightDensity = smoothstep(0.0, 0.75, 1 - Alt) * smoothstep(0.0, 0.2, Alt);

    float Base = texture(cloudNoise, (p.xz + Wind) * 0.0004).r;
    Base = pow(Base, cloudCoverageVl) * HeightDensity;

    return Base;
}

float noise_clouds(vec3 p) {
    float Base = noise_clouds_base(p);
    if (Base < 0.001) return 0;

    #ifdef SCREENSHOT_MODE
        vec2 Wind = vec2(0);
    #else
        vec2 Wind = windDirection * frameTimeCounter * 5;
    #endif

    vec2 D = vec2(textureNice(noisetex, (p.xy + Wind) * 0.0001).g, textureNice(noisetex, (p.xz + Wind) * 0.0001).g);
    vec3 Displacement = vec3(D.x, D.y, 1 - (D.x * D.x + D.y * D.y)) * 10;

    Base -= (1 - texture(worleyNoiseTexture, (p + Displacement) / vec3(64) * 0.75).r) * 0.03;
    // Detail *= 1 - texture(worleyNoiseTexture, (p) / vec3(64) * 0.25 + 0.33).r;
    Base -= texture(worleyNoiseTexture, (p) / vec3(64) * 0.125 + 0.5).r * 0.12;

    return clamp(Base, 0, 1);
}

float noise_smoke(vec3 p) {
    p.y *= 0.33;
    vec3 Wind = frameTimeCounter * vec3(0, 5.75, 0);

    vec2 D = vec2(textureNice(noisetex, (p.xy) * 0.00005).g, textureNice(noisetex, (p.xz) * 0.000066).g);
    vec3 Displacement = vec3(D.x, D.y, 1 - (D.x * D.x + D.y * D.y)) * 0.17;

    float Detail = texture(worleyNoiseTexture, (p - Wind * 0.3) / vec3(64) * 7.25 + Displacement).r;
    Detail *= texture(worleyNoiseTexture, (p - Wind) / vec3(64) * 0.75 + 0.5 + Displacement).r;

    return Detail * 1.5;
}


vec2 hash2(vec2 p) {
    p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
    return fract(sin(p) * 43758.5453);
}


// https://www.shadertoy.com/view/4ssfWM
float bayer8(vec2 a) {
    uvec2 b = uvec2(a);
    uint c = (b.x ^ b.y) << 1u;
    return float(
        ((c & 8u | b.y & 4u) >> 2u) |
            ((c & 4u | b.y & 2u) << 1u) |
            ((c & 2u | b.y & 1u) << 4u) //15 ops
    ) / 8. / 8.;
}

float dither(vec2 Pos, const bool AnimateNoise) {
    if(AnimateNoise) {
        float FrameMod = frameCounter % 64;
        Pos += 5.588238f * FrameMod;
    }

    return fract(52.9829189 * fract(0.06711056 * Pos.x + 0.00583715 * Pos.y));
}

vec4 blue_noise(vec2 Pos, const bool Animate) {
    vec4 Noise = texelFetch(blueNoiseTexture, ivec2(Pos) & 255, 0);

    if (Animate)
        Noise = fract(Noise + GOLDEN_RATIO * frameCounter); // Animate

    return Noise;
}

float random3D(vec3 p) {
    return fract(sin(dot(p, vec3(12.9898, 78.233, 45.543))) * 43758.5453);
}

// The following function is licensed under the MIT license
// Copyright © 2017,2024 Inigo Quilez
uint hash21( uvec2 p )
{
    p *= uvec2(73333,7777);
    p ^= (uvec2(3333777777u)>>(p>>28));
    uint n = p.x*p.y;
    return n^(n>>15);
}

float hash( vec2 p )
{
    uint h = hash21( floatBitsToUint(p) );
    
    return float(h)*(1.0/float(0xffffffffU));
}
