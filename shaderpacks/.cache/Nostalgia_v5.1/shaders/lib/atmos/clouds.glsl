const float edgeWeightStep = 1.0 - (1.0 / cloudVolumeRounding);

vec3 GetPlane(float Altitude, vec3 Direction) {
    return  Direction * ((Altitude - eyeAltitude) / Direction.y);
}

/*
float cloudTextureCubic(sampler2D tex, vec2 pos) {
    ivec2 texSize   = textureSize(tex, 0);

    vec4 samples    = textureGather(tex, pos, 3);

    vec2 weights    = fract(pos * texSize - 0.5);
        weights     = linStep(weights, edgeWeightStep, 1.0);
        weights     = cubeSmooth(weights);

    return mix(
        mix(samples.w, samples.z, weights.x),
        mix(samples.x, samples.y, weights.x), weights.y
    );
}
*/

/*
float cloudTextureCubic(sampler2D tex, vec2 pos) {
    ivec2 texSize   = textureSize(tex, 0);
    ivec2 pixelPos  = ivec2(fract(pos) * texSize);

    vec4 samples    = vec4(texelFetch(tex, pixelPos              , 0).a, texelFetch(tex, pixelPos + ivec2(1, 0), 0).a,
                           texelFetch(tex, pixelPos + ivec2(0, 1), 0).a, texelFetch(tex, pixelPos + ivec2(1, 1), 0).a);

    vec2 weights    = fract(pos * texSize);
        //weights     = linStep(weights, edgeWeightStep, 1.0);
        //weights     = cubeSmooth(weights);

    return mix(
        mix(samples.x, samples.y, weights.x),
        mix(samples.z, samples.w, weights.x), weights.y);
}*/

float cloudTextureCubic(sampler2D tex, vec2 pos) {
    ivec2 texSize = textureSize(tex, 0) * cloudVolumeRounding;
    vec2 texelSize = rcp(vec2(texSize));
    
    float p0q0 = texture(tex, pos).a;
    float p1q0 = texture(tex, pos + vec2(texelSize.x, 0)).a;

    float p0q1 = texture(tex, pos + vec2(0, texelSize.y)).a;
    float p1q1 = texture(tex, pos + vec2(texelSize.x , texelSize.y)).a;

    float a = cubeSmooth(fract(pos.x * texSize.x));

    float pInterp_q0 = mix(p0q0, p1q0, a);
    float pInterp_q1 = mix(p0q1, p1q1, a);

    float b = cubeSmooth(fract(pos.y*texSize.y));

    return mix(pInterp_q0, pInterp_q1, b);
}
float cloudTextureCubic(sampler2D tex, vec2 pos, const float RoundingMod) {
    ivec2 texSize = textureSize(tex, 0) * int(max(cloudVolumeRounding * RoundingMod, 1));
    vec2 texelSize = rcp(vec2(texSize));
    
    float p0q0 = texture(tex, pos).a;
    float p1q0 = texture(tex, pos + vec2(texelSize.x, 0)).a;

    float p0q1 = texture(tex, pos + vec2(0, texelSize.y)).a;
    float p1q1 = texture(tex, pos + vec2(texelSize.x , texelSize.y)).a;

    float a = cubeSmooth(fract(pos.x * texSize.x));

    float pInterp_q0 = mix(p0q0, p1q0, a);
    float pInterp_q1 = mix(p0q1, p1q1, a);

    float b = cubeSmooth(fract(pos.y*texSize.y));

    return mix(pInterp_q0, pInterp_q1, b);
}

const float phaseConst  = 1.0 / (pi * sqrt3);

float mieCloud(float cosTheta, float g) {
    float sqrG  = sqr(g);
    float a     = (1.0 - sqrG) * rcp(2.0 + sqrG);
    float b     = (1.0 + sqr(cosTheta)) * rcp((-2.0 * (g * cosTheta)) + 1.0 + sqrG);

    return max((1.5 * (a * b)) + (g * cosTheta), 0.0) * phaseConst;
}

float cloudPhase(float cosTheta, float g, vec3 gMult) {
    float x = mieCloud(cosTheta, gMult.x * g) * 0.71;
    float y = mieCloud(cosTheta, -gMult.y * g) * 0.71;
    float z = mieCloud(cosTheta, gMult.z * g);

    return mix(mix(x, y, 0.2), z, 0.15);    //i assume this is more energy conserving than summing them
}

float EstimateEnergy(float ratio) {
    return ratio / (1.0 - ratio);
}
float cloudPhase(float cosTheta, vec3 asymmetry) {
    float x = mieHG(cosTheta, asymmetry.x);
    float y = mieHG(cosTheta, -asymmetry.y);
    float z = mieCS(cosTheta, asymmetry.z);

    return 0.7 * x + 0.2 * y + 0.1 * z;
}
float cloudPhaseSky(float cosTheta, vec3 asymmetry) {
    float x = mieHG(cosTheta, asymmetry.x);
    float y = mieHG(cosTheta, -asymmetry.y);

    return 0.75 * x + 0.25 * y;
}

const vec2 RSKY_Volume0_Limits = vec2(cloudVolume0Alt, cloudVolume0Alt + cloudVolume0Depth);
const vec2 RSKY_Volume1_Limits = vec2(cloudVolume1Alt, cloudVolume1Alt + cloudVolume1Depth);

const float cloudScale  = 0.17 / 1024.0;
const float cloudVol0MaxY   = float(cloudVolume0Alt + cloudVolume0Depth);
const float cloudVol0MidY   = float(cloudVolume0Alt) + cloudVolume0Depth * 0.5;

const float cloudVol1MaxY   = float(cloudVolume1Alt + cloudVolume1Depth);
const float cloudVol1MidY   = float(cloudVolume1Alt) + cloudVolume1Depth * 0.5;

float cloudVolume0Shape(vec3 Position) {
    float Elevation = (Position.y - RSKY_Volume0_Limits.x) / cloudVolume0Depth;

    /*float fadeLow   = sstep(Position.y, float(RSKY_Volume0_Limits.x), float(RSKY_Volume0_Limits.x) + float(cloudVolume0Depth) * 0.02);
    float fadeHigh  = 1.0 - sstep(Position.y, RSKY_Volume0_Limits.y - float(cloudVolume0Depth) * 0.02, RSKY_Volume0_Limits.y);
    float erodeLow  = cube(1.0 - linStep(Position.y, float(RSKY_Volume0_Limits.x), float(RSKY_Volume0_Limits.x) + float(cloudVolume0Depth) * 0.2));
    float erodeHigh = cube(linStep(Position.y, float(RSKY_Volume0_Limits.x) + float(cloudVolume0Depth) * 0.8, RSKY_Volume0_Limits.y));*/

    vec4 ErosionFade = vec4(1.0 - linStep(Elevation, 0.0, 0.2),  //EL
                            linStep(Elevation, 0.8, 1.0),        //EH
                            sstep(Elevation, 0.0, 0.02),         //FL
                            1.0 - sstep(Elevation, 0.98, 1.0));  //FH
        ErosionFade.xy = cube(ErosionFade.xy);

    #ifdef freezeAtmosAnim
        Position.x  += float(atmosAnimOffset);
    #else
        #ifdef volumeWorldTimeAnim
            Position.x  += worldAnimTime * 600.0;
        #else
            Position.x  += frameTimeCounter;
        #endif
    #endif

        Position    *= cloudScale;

    float shape = cloudTextureCubic(CloudTexture, Position.xz);
        shape  -= ErosionFade.x + ErosionFade.y;
        shape  *= ErosionFade.z * ErosionFade.w;
        shape  -= 0.007;

    #ifdef cloudVolumeStoryMode
    float storyFade = linStep(Elevation, 0.15, 1.0);
        shape  *= (sqr(1.0 - storyFade)) * 0.999 + 0.001;
    #endif

        shape = mix(shape, shape * 0.15 + (ErosionFade.z * ErosionFade.w) * 0.08, wetness);

    return max0(shape * 2.15);
}

float cloudVolume0LightOD(vec3 pos, const uint steps, vec3 dir) {
    float stepSize      = float(cloudVolume0Depth) / float(steps);

    vec3 rStep  = dir * stepSize;

        pos    += rStep / pi;

    float od    = 0.0;

    for (uint i = 0; i < steps; ++i, pos += rStep) {

        if(pos.y > RSKY_Volume0_Limits.y || pos.y < RSKY_Volume0_Limits.x) continue;

        float density   = cloudVolume0Shape(pos);

            od += density * stepSize;
    }

    return od;
}

float cloudVolume0LightOD(vec3 pos, const uint steps, vec3 dir, float noise) {
    float stepSize      = float(cloudVolume0Depth) / float(steps);

    vec3 rStep  = dir * stepSize;

        pos    += rStep * noise + rStep / tau;

    float od    = 0.0;

    for (uint i = 0; i < steps; ++i, pos += rStep) {

        if(pos.y > RSKY_Volume0_Limits.y || pos.y < RSKY_Volume0_Limits.x) continue;
        
        float density   = cloudVolume0Shape(pos);

            od += density * stepSize;
    }

    return od;
}

float cloudVolume1Shape(vec3 Position) {
    float Elevation = (Position.y - RSKY_Volume1_Limits.x) / cloudVolume1Depth;

    /*float fadeLow   = sstep(pos.y, float(RSKY_Volume1_Limits.x), float(RSKY_Volume1_Limits.x) + float(cloudVolume1Depth) * 0.02);
    float fadeHigh  = 1.0 - sstep(pos.y, RSKY_Volume1_Limits.y - float(cloudVolume1Depth) * 0.02, RSKY_Volume1_Limits.y);
    float erodeLow  = cube(1.0 - linStep(pos.y, float(RSKY_Volume1_Limits.x), float(RSKY_Volume1_Limits.x) + float(cloudVolume1Depth) * 0.2));
    float erodeHigh = cube(linStep(pos.y, float(RSKY_Volume1_Limits.x) + float(cloudVolume1Depth) * 0.8, RSKY_Volume1_Limits.y));*/

    vec4 ErosionFade = vec4(1.0 - linStep(Elevation, 0.0, 0.2),  //EL
                            linStep(Elevation, 0.8, 1.0),        //EH
                            sstep(Elevation, 0.0, 0.02),         //FL
                            1.0 - sstep(Elevation, 0.98, 1.0));  //FH
        ErosionFade.xy = cube(ErosionFade.xy);

        Position.xz      = vec2(-Position.z, Position.x);

    #ifdef freezeAtmosAnim
        Position.x  += float(atmosAnimOffset);
    #else
        #ifdef volumeWorldTimeAnim
            Position.z  += worldAnimTime * 1.3 * 600.0;
        #else
            Position.z  += frameTimeCounter * 1.3;
        #endif
    #endif

        Position    *= cloudScale;

    float shape = cloudTextureCubic(CloudTexture, Position.xz);
        shape  -= ErosionFade.x + ErosionFade.y;
        shape  *= ErosionFade.z * ErosionFade.w;
        shape  -= 0.007;

    #ifdef cloudVolumeStoryMode
    float storyFade = linStep(Elevation, 0.15, 1.0);
        shape  *= (sqr(1.0 - storyFade)) * 0.999 + 0.001;
    #endif

        shape = mix(shape, shape * 0.15 + (ErosionFade.z * ErosionFade.w) * 0.08, wetness);

    return max0(shape * 2.15);
}

float cloudVolume1Shape_SmoothShadow(vec3 Position) {
    float Elevation = (Position.y - RSKY_Volume1_Limits.x) / cloudVolume1Depth;
    vec4 ErosionFade = vec4(1.0 - linStep(Elevation, 0.0, 0.2),  //EL
                            linStep(Elevation, 0.8, 1.0),        //EH
                            sstep(Elevation, 0.0, 0.02),         //FL
                            1.0 - sstep(Elevation, 0.98, 1.0));  //FH
        ErosionFade.xy = cube(ErosionFade.xy);

        Position.xz      = vec2(-Position.z, Position.x);

    #ifdef freezeAtmosAnim
        Position.x  += float(atmosAnimOffset);
    #else
        #ifdef volumeWorldTimeAnim
            Position.z  += worldAnimTime * 1.3 * 600.0;
        #else
            Position.z  += frameTimeCounter * 1.3;
        #endif
    #endif

        Position    *= cloudScale;

    float shape = cloudTextureCubic(CloudTexture, Position.xz, 1);
        shape  -= ErosionFade.x + ErosionFade.y;
        shape  *= ErosionFade.z * ErosionFade.w;
        shape  -= 0.007;

    #ifdef cloudVolumeStoryMode
    float storyFade = linStep(Elevation, 0.15, 1.0);
        shape  *= (sqr(1.0 - storyFade)) * 0.999 + 0.001;
    #endif

        shape = mix(shape, shape * 0.15 + (ErosionFade.z * ErosionFade.w) * 0.08, wetness);

    return max0(shape * 2.15);
}


float cloudVolume1LightOD(vec3 pos, const uint steps, vec3 dir) {
    float stepSize      = float(cloudVolume1Depth) / float(steps);

    vec3 rStep  = dir * stepSize;

        pos    += rStep / pi;

    float od    = 0.0;

    for (uint i = 0; i < steps; ++i, pos += rStep) {

        if(pos.y > RSKY_Volume1_Limits.y || pos.y < RSKY_Volume1_Limits.x) continue;

        float density   = cloudVolume1Shape(pos);

            od += density * stepSize;
    }

    return od;
}

float cloudVolume1LightOD(vec3 pos, const uint steps, vec3 dir, float noise) {
    float stepSize      = float(cloudVolume1Depth) / float(steps);

    vec3 rStep  = dir * stepSize;

        pos    += rStep * noise + rStep / tau;

    float od    = 0.0;

    for (uint i = 0; i < steps; ++i, pos += rStep) {

        if(pos.y > RSKY_Volume1_Limits.y || pos.y < RSKY_Volume1_Limits.x) continue;

        float density   = cloudVolume1Shape(pos);

            od += density * stepSize;
    }

    return od;
}

float cloudVolume0_SecondLayerOcclusion(vec3 pos, const uint steps, vec3 dir) {
    float stepSize      = float(cloudVolume1Depth) / float(steps);

    if (dir.y <= 0.0) return 0.0;

    pos += ((cloudVolume1Alt - pos.y) / dir.y) * dir;

    vec3 rStep  = dir * stepSize;

        pos    += rStep / pi;

    float od    = 0.0;

    for (uint i = 0; i < steps; ++i, pos += rStep) {

        if(pos.y > RSKY_Volume1_Limits.y || pos.y < RSKY_Volume1_Limits.x) continue;

        float density   = cloudVolume1Shape_SmoothShadow(pos);

            od += density * stepSize;
    }

    return od * sstep(dir.y, 0.1, 0.2);
}