/* RENDERTARGETS: 4 */
layout(location = 0) out vec4 skyCapture;

#include "/lib/head.glsl"

const vec2 viewSize     = vec2(512, 512);
const vec2 pixelSize    = 1.0 / viewSize;

in vec2 uv;

flat in mat2x3 skyColors;
flat in mat4x3 lightColor;

flat in vec3 sunDir;
flat in vec3 moonDir;

//uniform vec3 sunDir, moonDir;

uniform float wetness;

uniform vec3 cloudLightDir, lightDir;

uniform vec4 daytime;

uniform mat4 gbufferProjectionInverse, gbufferModelViewInverse;

#include "/lib/atmos/project.glsl"

#include "/lib/atmos/phase.glsl"


vec3 skyGradient(vec3 direction) {
    float vDotS     = dot(direction, sunDir);
    float vDotM     = dot(direction, moonDir);

    float horizon   = exp(-max0(direction.y) * sqrPi);
        horizon    *= exp(-max0(-direction.y) * pi);

    float sunAmb    = saturate(1.35 * mieHG(vDotS, 0.2) / 0.2);

        horizon     = mix(horizon, horizon * sunAmb, sqr(daytime.x + daytime.z) * 0.8);

    float zenith    = exp(-max0(direction.y)) * 0.8 + 0.2;

    vec3 sunColor   = lightColor[0] * 0.2;

    float sunScatter = mieHG(vDotS, 0.78) * rpi * (1 - daytime.w);

    float glowAmount = cube(1 - linStep(direction.y, 0.0, 0.31)) * 0.96 * sunAmb;

    vec3 glowColor  = mix(skyColors[1], sunColor * skyColors[1] * 0.9 + sunColor * sunScatter, sstep(sunDir.y, -0.1, 0.01));
        glowColor   = mix(glowColor * 0.5, skyColors[0] * 0.5, 1.0 - exp(-max0(-direction.y - 0.06) * 0.71) * 0.8);

    vec3 sky        = skyColors[0] * zenith;
        sky         = mix(sky, glowColor, glowAmount);
        sky         = mix(sky, skyColors[1] * 1.2, horizon);
        sky        += sunColor * sunScatter * 1.35 * sqrt3;
        sky        += lightColor[1] * mieHG(vDotM, 0.74) * rpi * sqrt(daytime.w);

    return sky;
}

#define CloudTexture colortex7

uniform sampler2D colortex7;
uniform sampler2D noisetex;

uniform int frameCounter;
uniform int worldTime;
uniform float worldAnimTime, cloudLightFlip, frameTimeCounter;

uniform vec3 cameraPosition;

flat in vec3 cloudSunlight;
flat in vec3 cloudSkylight;

const float eyeAltitude   = 64.0;

#include "/lib/frag/bluenoise.glsl"
#include "/lib/atmos/clouds.glsl"


vec4 RSKY_VanillaClouds(vec3 WorldDirection, float Dither, vec3 SkyColor) {
    vec4 Result = vec4(0,0,0,1);

    vec3 cameraPos      = vec3(cameraPosition.x, 64.0, cameraPosition.z);

    #define cameraPosition cameraPos

    vec3 DirectColor    = (worldTime>23000 || worldTime<12900) ? cloudSunlight : lightColor[1];
        DirectColor    *= cloudLightFlip / sqrt2;
    vec3 AmbientColor   = mix(cloudSkylight, lightColor[1] * (1.0 - sqrt(daytime.w)*0.96), 0.1) * euler;
    float vDotL         = dot(WorldDirection, cloudLightDir);

    bool IsVisible      = WorldDirection.y > 0.0;

    #ifdef cloudVolumeStoryMode
        const float SigmaA  = 0.5;
            AmbientColor       /= sqrt2;
        const float SigmaT  = 0.15;
    #else
        const float SigmaA  = 0.5;
        const float SigmaT  = 0.41;
    #endif

    const float Albedo = 0.93;
    const float ScatterMult = 1.0;

    if (IsVisible) {
        mat2x3 VolumeBounds = mat2x3(GetPlane(RSKY_Volume0_Limits.x, WorldDirection),
                                     GetPlane(RSKY_Volume0_Limits.y, WorldDirection));

        if (WorldDirection.y < 0.0) VolumeBounds = mat2x3(0.0);

        vec3 StartPos      = VolumeBounds[0];
        vec3 EndPos        = VolumeBounds[1];

        const float BaseStep = cloudVolume0Depth / (10.0);
        float StepLength = length((VolumeBounds[1] - VolumeBounds[0]) / (10.0));

        float StepCoeff = 0.5 + clamp(((StepLength / BaseStep) - 1.0) / sqrt2, 0.0, 1.0);
        uint StepCount  = uint(max(10.0 * StepCoeff, cloudVolume0Depth / euler));

        vec3 RStep          = (EndPos - StartPos) / float(StepCount);
        vec3 RPosition      = RStep * Dither + StartPos + cameraPosition;
        float RLength       = length(RStep);

        for (uint I = 0; I < StepCount; ++I, RPosition += RStep) {
            if (Result.a < 0.01) break;
            if (RPosition.y < RSKY_Volume0_Limits.x || RPosition.y > RSKY_Volume0_Limits.y) continue;

            float SampleDistance  = distance(RPosition, cameraPosition);
            if (SampleDistance > cloudVolume0Clip) continue;

            float Density = cloudVolume0Shape(RPosition);
            if (Density <= 0.0) continue;

            float StepOpticalDepth = Density * SigmaT * RLength;
            float StepTransmittance = exp(-StepOpticalDepth);
            float ScatterIntegral = (1.0 - StepTransmittance) / SigmaT;

            vec3 StepScattering = vec3(0);

            vec2 LightExtinction = vec2(cloudVolume0LightOD(RPosition, 5, cloudLightDir),
                                        cloudVolume0LightOD(RPosition, 4, vec3(0.0, 1.0, 0.0))
                                       ) * SigmaA;

            float AvgTransmittance = exp(-((tau / SigmaT) * Density));
            float BounceEstimate = EstimateEnergy(Albedo * (1.0 - AvgTransmittance));
            float BaseScatter = Albedo * (1.0 - StepTransmittance);
            vec3 PhaseG = pow(vec3(0.5, 0.35, 0.9), vec3((1.0 + (LightExtinction.x + Density * RLength) * SigmaT)));

            float DirScatterScale = pow(1.0 + 1.0 * LightExtinction.x * SigmaT, -1.0 / 1.0) * BounceEstimate;
            float AmbScatterScale = pow(1.0 + 1.0 * LightExtinction.y * SigmaT, -1.0 / 1.0) * BounceEstimate;

                StepScattering.xy = BaseScatter * vec2(cloudPhase(vDotL, PhaseG) * DirScatterScale,
                                                    cloudPhaseSky(WorldDirection.y, PhaseG * vec3(1,1,0.5)) * AmbScatterScale);

            vec3 SkyFade = exp(-SampleDistance * 2.8e-3 * vec3(1.0, 0.96, 0.85));
                SkyFade = mix(SkyFade, vec3(0), sstep(SampleDistance, float(cloudVolume0Clip) * 0.75, float(cloudVolume0Clip)));
                StepScattering = DirectColor * StepScattering.x + AmbientColor * StepScattering.y;
                StepScattering = mix(SkyColor * SigmaT * ScatterIntegral, StepScattering, SkyFade);

            Result = vec4((StepScattering * Result.a) + Result.rgb, Result.a * StepTransmittance);
        }

        Result.a = linStep(Result.a, 0.01, 1.0);
    }


    #ifdef cloudVolume1Enabled

    if (IsVisible) {
        mat2x3 VolumeBounds = mat2x3(GetPlane(RSKY_Volume1_Limits.x, WorldDirection),
                                     GetPlane(RSKY_Volume1_Limits.y, WorldDirection));

        if (WorldDirection.y < 0.0) VolumeBounds = mat2x3(0.0);

        vec3 StartPos      = VolumeBounds[0];
        vec3 EndPos        = VolumeBounds[1];

        const float BaseStep = cloudVolume1Depth / (6.0);
        float StepLength = length((VolumeBounds[1] - VolumeBounds[0]) / (6.0));

        float StepCoeff = 0.5 + clamp(((StepLength / BaseStep) - 1.0) / sqrt2, 0.0, 1.0);
        uint StepCount  = uint(max(6.0 * StepCoeff, cloudVolume1Depth / euler));

        vec3 RStep          = (EndPos - StartPos) / float(StepCount);
        vec3 RPosition      = RStep * Dither + StartPos + cameraPosition;
        float RLength       = length(RStep);

        vec4 LayerResult    = vec4(0,0,0,1);

        for (uint I = 0; I < StepCount; ++I, RPosition += RStep) {
            if (LayerResult.a < 0.01) break;
            if (RPosition.y < RSKY_Volume1_Limits.x || RPosition.y > RSKY_Volume1_Limits.y) continue;

            float SampleDistance  = distance(RPosition, cameraPosition);
            if (SampleDistance > cloudVolume1Clip) continue;

            float Density = cloudVolume1Shape(RPosition);
            if (Density <= 0.0) continue;

            float StepOpticalDepth = Density * SigmaT * RLength;
            float StepTransmittance = exp(-StepOpticalDepth);
            float ScatterIntegral = (1.0 - StepTransmittance) / SigmaT;

            vec3 StepScattering = vec3(0);

            vec2 LightExtinction = vec2(cloudVolume1LightOD(RPosition, 5, cloudLightDir),
                                        cloudVolume1LightOD(RPosition, 4, vec3(0.0, 1.0, 0.0))
                                       ) * SigmaA;

            float AvgTransmittance = exp(-((tau / SigmaT) * Density));
            float BounceEstimate = EstimateEnergy(Albedo * (1.0 - AvgTransmittance));
            float BaseScatter = Albedo * (1.0 - StepTransmittance);
            vec3 PhaseG = pow(vec3(0.5, 0.35, 0.9), vec3((1.0 + (LightExtinction.x + Density * RLength) * SigmaT)));

            float DirScatterScale = pow(1.0 + 1.0 * LightExtinction.x * SigmaT, -1.0 / 1.0) * BounceEstimate;
            float AmbScatterScale = pow(1.0 + 1.0 * LightExtinction.y * SigmaT, -1.0 / 1.0) * BounceEstimate;

                StepScattering.xy = BaseScatter * vec2(cloudPhase(vDotL, PhaseG) * DirScatterScale,
                                                    cloudPhaseSky(WorldDirection.y, PhaseG * vec3(1,1,0.5)) * AmbScatterScale);

            vec3 SkyFade = exp(-SampleDistance * (2.8e-3 * vec3(1.0) * 0.9));
                SkyFade = mix(SkyFade, vec3(0), sstep(SampleDistance, float(cloudVolume1Clip) * 0.75, float(cloudVolume1Clip)));
                StepScattering = DirectColor * StepScattering.x + AmbientColor * StepScattering.y;
                StepScattering = mix(SkyColor * SigmaT * ScatterIntegral, StepScattering, SkyFade);

            LayerResult = vec4((StepScattering * LayerResult.a) + LayerResult.rgb, LayerResult.a * StepTransmittance);
        }

        LayerResult.a       = linStep(LayerResult.a, 0.01, 1.0);

        Result.rgb    += LayerResult.rgb * Result.a;

        Result.a *= LayerResult.a;
    }
    #endif

    #undef cameraPosition

    Result      = mix(Result, vec4(0,0,0,1), exp(-max0(WorldDirection.y * pi4)));

    return Result;
}

/* ------ cloud shadows ------ */

uniform mat4 shadowModelViewInverse;

vec3 GetShadowPlane(float Altitude, float CaptureAltitude, vec3 Direction) {
    return  Direction * ((Altitude - CaptureAltitude) / Direction.y);
}

float generateCloudShadowmap(vec2 uv, vec3 LightDirection, float dither) {
    vec3 position   = vec3(uv, 0.0) * 2.0 - 1.0;
        position.xy *= cloudShadowmapRenderDistance;
        position    = mat3(shadowModelViewInverse) * position;
        position.xyz += cameraPosition.xyz;
        //position    += lightDir * (256.0 - position.y) * rcp(lightDir.y);

    float lightFade = cubeSmooth(sqr(linStep(LightDirection.y, 0.1, 0.15)));

    float Transmittance = 1.0;

    #ifdef cloudVolumeStoryMode
        const float SigmaA  = 0.5;
        const float SigmaT  = 0.15 * euler;
    #else
        const float SigmaA  = 0.5;
        const float SigmaT  = 0.41 / sqrt2;
    #endif

    if (lightFade > 0.0) {
        vec3 Plane0 = GetShadowPlane(cloudVol0MidY, position.y, LightDirection) + position;
        float Fade0 = 1.0 - sstep(distance(Plane0.xz, cameraPosition.xz), cloudShadowmapRenderDistance * 0.5, cloudShadowmapRenderDistance);

        if (Fade0 > 1e-3) {
            float Density = cloudVolume0Shape(Plane0);
            float StepTransmittance = exp(-Density * SigmaT * SigmaA * cloudVolume0Depth / pi);
            StepTransmittance = mix(1.0, StepTransmittance, Fade0);
            Transmittance *= StepTransmittance;
        }

        #ifdef cloudVolume1Enabled
        vec3 Plane1 = GetShadowPlane(cloudVol1MidY, position.y, LightDirection) + position;
        float Fade1 = 1.0 - sstep(distance(Plane1.xz, cameraPosition.xz), cloudShadowmapRenderDistance * 0.5, cloudShadowmapRenderDistance);
        if (Fade1 > 1e-3) {
            float Density = cloudVolume1Shape_SmoothShadow(Plane1);
            float StepTransmittance = exp(-Density * SigmaT * SigmaA * cloudVolume0Depth / tau);
            StepTransmittance = mix(1.0, StepTransmittance, Fade1);
            Transmittance *= StepTransmittance;
        }
        #endif
    }

    Transmittance = mix(1.0, Transmittance, lightFade);

    return saturate(Transmittance);
}

void main() {
    vec2 projectionUV   = fract(uv * vec2(1.0, 2.0));

    skyCapture = vec4(0,0,0,1);

    if (uv.y < 0.5) {
        // Clear Sky Capture
        vec3 direction  = unprojectSky(projectionUV);

        skyCapture.rgb      = skyGradient(direction);
    } else {
        // Sky Capture with Clouds (for Reflections)
        vec3 direction  = unprojectSky(projectionUV);

        skyCapture.rgb      = skyGradient(direction);
        skyCapture.rgb     *= mix(exp(-max0(-direction.y) * cube(euler)), 1.0, 0.2);

        #ifdef cloudVolumeEnabled
        vec4 clouds     = RSKY_VanillaClouds(direction, ditherBluenoiseStatic(), skyCapture.rgb);

        skyCapture.rgb      = skyCapture.rgb * clouds.a + clouds.rgb;
        #endif
    }
    #ifdef cloudShadowsEnabled
    skyCapture.a = generateCloudShadowmap(uv, lightDir, ditherBluenoiseStatic());
    #endif
}