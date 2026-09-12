#version 400 compatibility

/*
====================================================================================================

    Copyright (C) 2023 RRe36

    All Rights Reserved unless otherwise explicitly stated.


    By downloading this you have agreed to the license and terms of use.
    These can be found inside the included license-file
    or here: https://rre36.com/copyright-license

    Violating these terms may be penalized with actions according to the Digital Millennium
    Copyright Act (DMCA), the Information Society Directive and/or similar laws
    depending on your country.

====================================================================================================
*/

/* RENDERTARGETS: 0,5,7,8 */
layout(location = 0) out vec3 sceneColor;
layout(location = 1) out vec4 fogScattering;
layout(location = 2) out vec3 fogTransmittance;
layout(location = 3) out vec4 cloudPostFog;


#include "/lib/head.glsl"
#include "/lib/util/encoders.glsl"

const bool shadowHardwareFiltering = true;

in vec2 uv;

flat in mat4x3 lightColor;

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex3;
uniform sampler2D colortex4;
uniform sampler2D colortex5;
uniform sampler2D colortex7;
uniform sampler2D colortex10;
uniform sampler2D colortex11;

uniform sampler2D depthtex0;
uniform sampler2D depthtex1;

uniform sampler2D noisetex;
//uniform sampler2D CloudTexture;

#define CloudTexture colortex7

uniform sampler2DShadow shadowtex0;
uniform sampler2DShadow shadowtex1;
uniform sampler2D shadowcolor0;

uniform int frameCounter;
uniform int isEyeInWater;
uniform int worldTime;

uniform float eyeAltitude, wetness;
uniform float far, near;
uniform float frameTimeCounter;
uniform float cloudLightFlip;
uniform float sunAngle;
uniform float lightFlip;
uniform float worldAnimTime;

uniform ivec2 eyeBrightnessSmooth;

uniform vec2 taaOffset;
uniform vec2 viewSize, pixelSize;

uniform vec3 cameraPosition;
uniform vec3 lightDirView, lightDir;
uniform vec3 cloudLightDir, cloudLightDirView;

uniform vec4 daytime;

uniform mat4 gbufferProjectionInverse, gbufferModelViewInverse;
uniform mat4 gbufferProjection, gbufferModelView;
uniform mat4 shadowModelView, shadowModelViewInverse;
uniform mat4 shadowProjection, shadowProjectionInverse;

#define FUTIL_LINDEPTH
#include "/lib/fUtil.glsl"

#include "/lib/frag/bluenoise.glsl"
#include "/lib/frag/gradnoise.glsl"

#include "/lib/util/bicubic.glsl"
#include "/lib/util/transforms.glsl"
#include "/lib/atmos/project.glsl"
#include "/lib/atmos/phase.glsl"
#include "/lib/atmos/waterConst.glsl"

vec3 getFog(vec3 color, float dist, vec3 skyColor, vec3 sceneDir) {
	    dist 	= dist / far;
		dist 	= max((dist - fogStart), 0.0);
        dist   /= 1.0 - fogStart;
        
	float alpha = 1.0-exp(-dist * fogFalloff);
        alpha *= alpha;
        alpha  *= cube(1.0 - max0(sceneDir.y));

	color 	= mix(color, skyColor, saturate(alpha));

	return color;
}

vec3 getWaterFog(vec3 SceneColor, float dist, vec3 ScatterColor){
    float density   = max0(dist) * waterDensity;

    vec3 transmittance = expf(-waterAbsorbCoeff * density);

    const vec3 scatterCoeff = vec3(waterRed, waterGreen, waterBlue);

    vec3 scatter    = 1.0-exp(-density * scatterCoeff);
        scatter    *= max(expf(-waterAttenCoeff * density), expf(-waterAttenCoeff * pi));

    return SceneColor * transmittance + scatter * ScatterColor * rpi;
}

#include "/lib/light/warp.glsl"
#include "/lib/frag/noise.glsl"

vec3 getShadowmapPos(vec3 scenePos, const float bias) {  //shadow 2d
    vec3 pos    = scenePos + vec3(bias) * lightDir;
    float a     = length(pos);
        pos     = transMAD(shadowModelView, pos);
        pos     = projMAD(shadowProjection, pos);
        pos.z  *= 0.2;
        pos.z  -= 0.0012*(saturate(a/256.0));

        pos.xy  = shadowmapWarp(pos.xy);

    return pos*0.5+0.5;
}
vec3 toShadowmapTexturePos(vec3 shadowPos) {
    //shadowPos.z    *= 0.2;
    shadowPos.xy    = shadowmapWarp(shadowPos.xy) * 0.5 + 0.5;

    return shadowPos;
}

float readCloudShadowmap(sampler2D shadowmap, vec3 position) {
    position    = mat3(shadowModelView) * position;
    position   /= cloudShadowmapRenderDistance;
    position.xy = position.xy * 0.5 + 0.5;

    return texture(shadowmap, position.xy).a;
}

vec3 getShadowcol(sampler2D tex, vec2 coord) {
    vec4 x  = texture(tex, coord);
        x.rgb = sqr(x.rgb);

    if (x.a < 0.97 && x.a > 0.93) {
        x.rgb = vec3(0.1, 0.2, 1.0);
    }

    return mix(vec3(1.0), x.rgb, x.a);
}

/* ------ volumetric fog ------ */

const float airMieG   = 0.7;

const vec3 airRayleighCoeff     = vec3(3.54e-6, 5.47e-6, 7.62e-6);
const vec3 airMieCoeff          = vec3(9e-6);    //19e-5 for rain

const mat2x3 airScatterMat      = mat2x3(airRayleighCoeff, airMieCoeff);
const mat2x3 airExtinctMat      = mat2x3(airRayleighCoeff, airMieCoeff);

const vec3 fogMistCoeff         = vec3(4e-3);
const mat3x3 fogScatterMat      = mat3x3(airRayleighCoeff, airMieCoeff, fogMistCoeff);
const mat3x3 fogExtinctMat      = mat3x3(airRayleighCoeff, airMieCoeff * 1.1, fogMistCoeff);

const vec2 fogFalloffScale  = 1.0 / vec2(4e1, 25e1);
const vec2 fogAirScale      = vec2(100.0, 1e2);

vec2 airPhaseFunction(float cosTheta) {
    return vec2(rayleighPhase(cosTheta), mieCS(cosTheta, airMieG));
}
float airMieBackscatter(float cosTheta) {
    return mieHG(cosTheta, -airMieG * rcp(pi));
}
float fogMistPhase(float cosTheta, float density) {
    return mix(mieCS(cosTheta, pow(airMieG, 1.0 + density)), airMieBackscatter(cosTheta), 0.19);
}

uniform vec3 fogDensityCoeff;

#define fogMistAltitude 100.0
#define airDensity 1.0

#ifdef volumeWorldTimeAnim
    float fogTime     = worldAnimTime * 3.6;
#else
    float fogTime     = frameTimeCounter * 0.006;
#endif

float mistDensity(vec3 rPos, float altitude) {
    vec3 wind   = vec3(fogTime, 0.0, fogTime * 0.5);
    float noise = value3D(rPos * 0.037 + wind) + value3D(rPos * 0.08 + wind * 3.0) * 0.5;

    float mist  = expf(-max0((altitude - 64.0) * 0.01));
        mist    = sstep(noise * rcp(1.5) - (1.0 - mist) * 0.5, 0.33, 0.6);
        mist   *= sqr(1.0 - linStep(altitude, 85.0, fogMistAltitude));

    return mist * fogDensityCoeff.z;
}

vec3 fogAirDensity(vec3 rPos, float altitude, bool terrain) {
    //float dist  = length(rPos);
    rPos   += cameraPosition;

    float maxFade = sqr(1.0 - linStep(altitude, 144.0, 256.0));

    vec2 rm     = expf(-max0((altitude - 66.0) * fogFalloffScale));
    //rm.y *= 0;
    float mist  = 0.0;
    if (fogDensityCoeff.z > 1e-5) mist = mistDensity(rPos, altitude);
    //if (terrain) rm *= 1.0 + sstep(dist, far * 0.6, far) * pi * 50.0;

    return vec3(rm * fogAirScale * fogDensityCoeff.xy * maxFade * fogDensityMult, mist);
}

float fogMistLightOD(vec3 pos) {
    float stepsize = 12.0;

    const int steps = 2;

    float od = 0.0;

    for(uint i = 0; i < steps; ++i, pos += lightDir * stepsize) {

        if(pos.y > fogMistAltitude || pos.y < 0.0) continue;
        
        float density = mistDensity(pos, pos.y);
        if (density <= 0.0) continue;

            od += density * stepsize;
    }

    return od;
}

mat2x3 volumetricFog(vec3 scenePos, vec3 sceneDir, bool isSky, float vDotL, float dither, float cave) {
    float topDist    = length(sceneDir * ((256.0 - eyeAltitude) * rcp(sceneDir.y)));
    float bottomDist = length(sceneDir * ((-32.0 - eyeAltitude) * rcp(sceneDir.y)));

    float volumeHull = sceneDir.y > 0.0 ? topDist : bottomDist;

    float endDist   = isSky ? min(volumeHull, min(fogClipDist, far)) : length(scenePos);
    float startDist = eyeAltitude > 256.0 ? topDist : 1.0;

    vec3 startPos   = eyeAltitude > 256.0 ? sceneDir * startDist : vec3(0.0);
        startPos   += gbufferModelViewInverse[3].xyz;
    vec3 endPos     = isSky ? sceneDir * endDist : scenePos;

    float baseStep  = length(endPos - startPos);
    float stepCoeff = saturate(baseStep * rcp(clamp(far, 256.0, 512.0)));

    uint steps      = fogMinSteps + uint(stepCoeff * fogAdaptiveSteps);

    vec3 rStep      = (endPos - startPos) / float(steps);
    vec3 rPos       = startPos + rStep * dither;
    float rLength   = length(rStep);

    vec3 shadowStartPos = transMAD(shadowModelView, (startPos));
        shadowStartPos  = projMAD(shadowProjection, shadowStartPos);
        shadowStartPos.z *= 0.2;
    vec3 shadowEndPos   = transMAD(shadowModelView, (endPos));
        shadowEndPos    = projMAD(shadowProjection, shadowEndPos);
        shadowEndPos.z *= 0.2;

    vec3 shadowStep = (shadowEndPos - shadowStartPos) / float(steps);
    vec3 shadowPos  = shadowStartPos + shadowStep * dither;

    mat2x3 scattering = mat2x3(0.0);
    vec3 transmittance = vec3(1.0);

    vec3 phase;
        phase.xy    = airPhaseFunction(vDotL);
        phase.z     = mix(mieCS(vDotL, airMieG * mistMieAnisotropy), airMieBackscatter(vDotL), mistMieAnisotropy / 4.0);
    float phaseIso  = 0.25;

    vec3 sunlight       = sunAngle < 0.5 ? lightColor[0] : lightColor[1];
        sunlight       *= lightFlip * sqrt2;
    vec3 skylight       = lightColor[2] * cave;
        skylight       += vec3(0.05, 0.4, 1.0) * 0.12 * (1-cave);

    #ifdef UseLightleakPrevention
        sunlight       *= cave;
    #endif

    float pFade         = saturate(mieHG(vDotL, 0.65));

    uint i = 0;
    do {
        rPos += rStep; shadowPos += shadowStep;
        if (length(rPos) > length(scenePos) && !isSky) break;
    //for (uint i = 0; i < steps; ++i, rPos += rStep, shadowPos += shadowStep) {
        if (maxOf(transmittance) < 0.01) break;

        float altitude  = rPos.y + eyeAltitude;

        if (altitude > 256.0) continue;

        vec3 density    = fogAirDensity(rPos, altitude, !isSky);
            density.x   = mix(density.x, 250.0, (1-cave) * expf(-max0((altitude - 50.0) * 0.01)));

        //if (maxOf(density) < 1e-32) continue;

        vec3 stepRho    = density * rLength;
        vec3 od         = fogExtinctMat * stepRho;

        vec3 stepT      = expf(-od);
        vec3 scatterInt = saturate((stepT - 1.0) * rcp(-max(od, 1e-16)));
        vec3 visScatter = transmittance * scatterInt;

        #ifdef fogMistAdvanced
            if (density.z > 0.0) {
                float mistLightOD = fogMistLightOD(rPos + cameraPosition);

                float mistLighting  = expf(-stepRho.z) * pow(1.0 + 1.0 * 0.7 * mistLightOD, -1.0 / 0.7);
                    mistLighting    = mix(pi * (1.0 - 0.6 * expf(-density.z * 28.0)), 1.0, pFade);
                    mistLighting    = fogMistPhase(vDotL, mistLightOD);
                phase.z     = mistLighting;
            }
        #else
            if (density.z > 0.0) {
                phase.z     = fogMistPhase(vDotL, density.z) * (2.0 - pFade);
            }
        #endif

        vec3 sunScatter = fogScatterMat * (stepRho * phase) * visScatter;
        vec3 skyScatter = fogScatterMat * (stepRho * phaseIso) * visScatter;

        vec3 shadowCoord = vec3(shadowmapWarp(shadowPos.xy), shadowPos.z) * 0.5 + 0.5;

        float shadow0   = texture(shadowtex0, shadowCoord);

        float shadow    = 1.0;
        vec3 shadowCol  = vec3(1.0);
        
        if (shadow0 < 1.0) {
            shadow      = texture(shadowtex1, shadowCoord);

            if (abs(shadow - shadow0) > 0.1) {
                shadowCol   = getShadowcol(shadowcolor0, shadowCoord.xy);
            }
        }

        #ifdef cloudShadowsEnabled
        shadow         *= mix(readCloudShadowmap(colortex4, rPos), 1.0, sstep(altitude, cloudVolume0Alt, cloudVolume0Alt + cloudVolume0Depth * euler));
        #endif

        scattering[0]  += (sunScatter * shadowCol * transmittance) * shadow;
        scattering[1]  += skyScatter * transmittance;

        transmittance  *= stepT;
    } while (++i < steps);

    vec3 color  = scattering[0] * sunlight + scattering[1] * skylight;

    if (color != color) {   //because NaNs on nVidia don't need a logic cause to happen
        color = vec3(0.0);
        transmittance = vec3(1.0);
    }

    return mat2x3(color, transmittance);
}

void applyFogData(inout vec3 color, in mat2x3 data) {
    color = color * data[1] + data[0];
}

/* --- TEMPORAL CHECKERBOARD --- */

#define checkerboardDivider 4
#define ditherPass
#include "/lib/frag/checkerboard.glsl"


flat in vec3 cloudSunlight;
flat in vec3 cloudSkylight;
//#define colortex7 CloudTexture
#include "/lib/atmos/clouds.glsl"

vec4 RSKY_VanillaClouds(vec3 WorldDirection, vec3 WorldPosition, float Dither, bool IsTerrain, vec3 SkyColor, out float HitDistance) {
    vec4 Result = vec4(0,0,0,1);

    vec3 DirectColor    = (worldTime>23000 || worldTime<12900) ? cloudSunlight : lightColor[1];
        DirectColor    *= cloudLightFlip / sqrt2;
    vec3 AmbientColor   = mix(cloudSkylight, lightColor[1] * (1.0 - sqrt(daytime.w)*0.96), 0.1) * euler;
    float vDotL         = dot(WorldDirection, cloudLightDir);

    float IsWithin      = sstep(eyeAltitude, float(RSKY_Volume0_Limits.x) - 15.0, float(RSKY_Volume0_Limits.x)) * (1.0 - sstep(eyeAltitude, RSKY_Volume0_Limits.y, RSKY_Volume0_Limits.y + 15.0));
    bool IsBelow        = eyeAltitude < cloudVol0MidY;
    bool IsVisible      = WorldDirection.y > 0.0 && IsBelow || WorldDirection.y < 0.0 && !IsBelow;

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

    HitDistance     = far * 2.0;

    if (IsVisible || IsWithin > 0.0) {
        mat2x3 VolumeBounds = mat2x3(GetPlane(RSKY_Volume0_Limits.x, WorldDirection),
                                     GetPlane(RSKY_Volume0_Limits.y, WorldDirection));

        if (WorldDirection.y < 0.0 && IsBelow ||
            WorldDirection.y > 0.0 && !IsBelow) VolumeBounds = mat2x3(0.0);

        vec3 StartPos      = IsBelow ? VolumeBounds[0] : VolumeBounds[1];
        vec3 EndPos        = IsBelow ? VolumeBounds[1] : VolumeBounds[0];
            StartPos       = mix(StartPos, gbufferModelViewInverse[3].xyz, IsWithin);
            EndPos         = mix(EndPos, WorldDirection * cloudVolume0Clip / pi, IsWithin);

        if (IsTerrain) {
            if (length(EndPos) > length(WorldPosition)) EndPos = WorldPosition;
        }

        const float BaseStep = cloudVolume0Depth / (float(cloudVolume0Samples));
        float StepLength = abs(distance(StartPos, EndPos) / float(cloudVolume0Samples));

        float StepCoeff = 0.5 + clamp(((StepLength / BaseStep) - 1.0) / sqrt2, 0.0, 1.0);
        uint StepCount  = uint(max(cloudVolume0Samples * StepCoeff, cloudVolume0Depth / euler));

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

            HitDistance = min(HitDistance, SampleDistance);

            float StepOpticalDepth = Density * SigmaT * RLength;
            float StepTransmittance = exp(-StepOpticalDepth);

            vec3 StepScattering = vec3(0);

            vec2 LightExtinction = vec2(cloudVolume0LightOD(RPosition, 5, cloudLightDir),
                                        cloudVolume0LightOD(RPosition, 4, vec3(0.0, 1.0, 0.0))
                                       ) * SigmaA;

            #ifdef cloudLayerShadowing
            #ifdef cloudVolume1Enabled
                LightExtinction += vec2(cloudVolume0_SecondLayerOcclusion(RPosition, 3, cloudLightDir) / euler,
                                        cloudVolume0_SecondLayerOcclusion(RPosition, 3, vec3(0.0, 1.0, 0.0)) / tau
                                       ) * SigmaA;
            #endif
            #endif

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
                StepScattering = mix(SkyColor * (1.0 - StepTransmittance), StepScattering, SkyFade);

            Result = vec4((StepScattering * Result.a) + Result.rgb, Result.a * StepTransmittance);
        }

        Result.a = linStep(Result.a, 0.01, 1.0) * 0.99 + 0.01;

        Result      = mix(Result, vec4(0,0,0,1), exp(-max0(WorldDirection.y * pi4)) * (1.0 - sstep(eyeAltitude, RSKY_Volume0_Limits.x - 16.0, RSKY_Volume0_Limits.x)));
    }


    #ifdef cloudVolume1Enabled
    IsWithin    = sstep(eyeAltitude, float(cloudVolume1Alt) - 15.0, float(cloudVolume1Alt)) * (1.0 - sstep(eyeAltitude, cloudVol1MaxY, cloudVol1MaxY + 15.0));
    IsBelow     = eyeAltitude < cloudVol1MidY;
    IsVisible   = WorldDirection.y > 0.0 && IsBelow || WorldDirection.y < 0.0 && !IsBelow;

    if (IsVisible || IsWithin > 0.0) {
        mat2x3 VolumeBounds = mat2x3(GetPlane(RSKY_Volume1_Limits.x, WorldDirection),
                                     GetPlane(RSKY_Volume1_Limits.y, WorldDirection));

        if (WorldDirection.y < 0.0 && IsBelow ||
            WorldDirection.y > 0.0 && !IsBelow) VolumeBounds = mat2x3(0.0);

        vec3 StartPos      = IsBelow ? VolumeBounds[0] : VolumeBounds[1];
        vec3 EndPos        = IsBelow ? VolumeBounds[1] : VolumeBounds[0];
            StartPos       = mix(StartPos, gbufferModelViewInverse[3].xyz, IsWithin);
            EndPos         = mix(EndPos, WorldDirection * cloudVolume1Clip / pi, IsWithin);

        if (IsTerrain) {
            if (length(EndPos) > length(WorldPosition)) EndPos = WorldPosition;
        }

        const float BaseStep = cloudVolume1Depth / (float(cloudVolume1Samples));
        float StepLength = abs(distance(StartPos, EndPos) / float(cloudVolume1Samples));

        float StepCoeff = 0.5 + clamp(((StepLength / BaseStep) - 1.0) / sqrt2, 0.0, 1.0);
        uint StepCount  = uint(max(cloudVolume1Samples * StepCoeff, cloudVolume1Depth / euler));

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

            HitDistance = min(HitDistance, SampleDistance);

            float StepOpticalDepth = Density * SigmaT * RLength;
            float StepTransmittance = exp(-StepOpticalDepth);

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
                StepScattering = mix(SkyColor * (1.0 - StepTransmittance), StepScattering, SkyFade);

            LayerResult = vec4((StepScattering * LayerResult.a) + LayerResult.rgb, LayerResult.a * StepTransmittance);
        }

        LayerResult.a       = linStep(LayerResult.a, 0.01, 1.0) * 0.99 + 0.01;

        LayerResult      = mix(LayerResult, vec4(0,0,0,1), exp(-max0(WorldDirection.y * pi4)) * (1.0 - sstep(eyeAltitude, RSKY_Volume1_Limits.x - 16.0, RSKY_Volume1_Limits.x)));


        if (eyeAltitude < cloudVolume1Alt) {
            Result.rgb    += LayerResult.rgb * Result.a;
        } else {
            Result.rgb     = Result.rgb * LayerResult.a + LayerResult.rgb;
        }

        Result.a *= LayerResult.a;
    }
    #endif
    return Result;
}

mat2x3 unpackReflectionAux(vec4 data){
    vec3 shadows    = decodeRGBE8(vec4(unpack2x8(data.x), unpack2x8(data.y)));
    vec3 albedo     = decodeRGBE8(vec4(unpack2x8(data.z), unpack2x8(data.w)));

    return mat2x3(shadows, albedo);
}


/* ------ Refraction ------ */

vec3 refract2(vec3 I, vec3 N, vec3 NF, float eta) {     //from spectrum by zombye
    float NoI = dot(N, I);
    float k = 1.0 - eta * eta * (1.0 - NoI * NoI);
    if (k < 0.0) {
        return vec3(0.0); // Total Internal Reflection
    } else {
        float sqrtk = sqrt(k);
        vec3 R = (eta * dot(NF, I) + sqrtk) * NF - (eta * NoI + sqrtk) * N;
        return normalize(R * sqrt(abs(NoI)) + eta * I);
    }
}


void main() {
    sceneColor  = texture(colortex0, uv).rgb;

    vec4 GBuffer0       = texture(colortex1, uv);

    vec4 GBuffer1       = texture(colortex2, uv);
    int matID           = int(unpack2x8(GBuffer1.y).x * 255.0);

    vec4 translucencyColor  = texture(colortex5, uv);

    vec2 sceneDepth     = vec2(texture(depthtex0, uv).x, texture(depthtex1, uv).x);
    bool translucent    = sceneDepth.x < sceneDepth.y;

    vec3 position0      = vec3(uv / ResolutionScale, sceneDepth.x);
        position0       = screenToViewSpace(position0);

    vec3 position1      = vec3(uv / ResolutionScale, sceneDepth.y);
        position1       = screenToViewSpace(position1);

    mat2x3 scenePos     = mat2x3(viewToSceneSpace(position0), viewToSceneSpace(position1));

    vec3 worldDir       = mat3(gbufferModelViewInverse) * normalize(position0);
    vec3 worldDir1       = mat3(gbufferModelViewInverse) * normalize(position1);

    bool water          = matID == 102;
    
    if (water){
        vec3 sceneNormal    = decodeNormal(GBuffer0.xy);
        vec3 viewNormal     = mat3(gbufferModelView) * sceneNormal;

        vec3 flatNormal     = clampDIR(normalize(cross(dFdx(scenePos[0]), dFdy(scenePos[0]))));
        vec3 flatViewNormal = normalize(mat3(gbufferModelView) * flatNormal);

        vec3 normalCorrected = dot(viewNormal, normalize(position1)) > 0.0 ? -viewNormal : viewNormal;

        vec3 refractedDir   = clampDIR(refract2(normalize(position1), normalCorrected, flatViewNormal, rcp(1.33)));
        //vec3 refractedDir   = refract(normalize(viewPos1), normalCorrected, rcp(1.33));

        float refractedDist = distance(position0, position1);

        vec3 refractedPos   = position1 + refractedDir * refractedDist;

        vec3 screenPos      = viewToScreenSpace(refractedPos);

        float distToEdge    = maxOf(abs(screenPos.xy * 2.0 - 1.0));
            distToEdge      = sqr(sstep(distToEdge, 0.7, 1.0));

            screenPos.xy    = mix(screenPos.xy, uv / ResolutionScale, distToEdge);

        //vec2 refractionDelta = coord - screenPos.xy;

        float refractedDepth = texture(depthtex1, screenPos.xy * ResolutionScale).x;

        if (refractedDepth > sceneDepth.x) {
            sceneDepth.y = refractedDepth;
            position1   = screenToViewSpace(vec3(screenPos.xy, sceneDepth.y));
            scenePos[1] = viewToSceneSpace(position1);

            sceneColor.rgb  = texture(colortex0, screenPos.xy * ResolutionScale).rgb;

            worldDir1    = clampDIR(normalize(scenePos[1]));
        }
    }

    vec3 skyColor       = clamp16F(texture(colortex4, projectSky(worldDir, 0)).rgb);

    #ifdef cloudVolumeEnabled
        float cloudDistance = far * 2.0;
        vec4 cloudData  = RSKY_VanillaClouds(worldDir, scenePos[0], ditherBluenoise(), landMask(sceneDepth.y), skyColor, cloudDistance);

        bool Clouds_PreFog = (!landMask(sceneDepth.x) && eyeAltitude < RSKY_Volume0_Limits.x) || (length(scenePos[0]) <= cloudDistance);

        if (Clouds_PreFog) {
            sceneColor  = sceneColor * cloudData.a + cloudData.rgb;
        }
    #endif

    mat2x3 reflectionAux = unpackReflectionAux(texture(colortex3, uv));

    vec3 translucencyAbsorption = reflectionAux[1];

    float vDotL     = clampDIR(dot(normalize(position1), lightDirView));

    float caveMult  = linStep(eyeBrightnessSmooth.y/240.0, 0.1, 0.9);

    if (matID == 102 && isEyeInWater == 0) {
        #ifdef waterFogEnabled
        sceneColor = getWaterFog(sceneColor, max0(distance(position0, position1)), lightColor[2] * caveMult);
        translucencyAbsorption  = vec3(1);
        #endif
    } else if (landMask(sceneDepth.y)) {
        #ifdef fogEnabled
        sceneColor  = getFog(sceneColor, distance(position0, position1), skyColor, worldDir1);
        #endif
    }

    if (translucent) sceneColor = sceneColor * saturate(translucencyAbsorption) * (1.0 - translucencyColor.a) + translucencyColor.rgb;

    fogScattering   = vec4(0.0);
    fogTransmittance = vec3(1.0);

    #ifdef fogVolumeEnabled
        {
            float vDotL     = dot(normalize(position0), lightDirView);
            bool isSky      = !landMask(sceneDepth.x);

            mat2x3 fogData  = mat2x3(vec3(0.0), vec3(1.0));

            if (isEyeInWater == 0) {
                fogData    = volumetricFog(scenePos[0], worldDir, isSky, vDotL, ditherBluenoise(), caveMult);
            }

            fogScattering.rgb = fogData[0];
            fogScattering.a = depthLinear(sceneDepth.x);
            fogTransmittance = fogData[1];
        }

        fogScattering       = clamp16F(fogScattering);
    #endif  

    cloudPostFog = vec4(0,0,0,1);

    #ifdef cloudVolumeEnabled
    if (!Clouds_PreFog) {
        //sceneColor  = sceneColor * cloudData.a + cloudData.rgb;
        cloudPostFog = cloudData;
    }
    #endif

    //sceneColor.rgb = stex(colortex10).rgb;
}