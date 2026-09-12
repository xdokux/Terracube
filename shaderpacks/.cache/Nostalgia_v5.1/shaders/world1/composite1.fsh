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

/* RENDERTARGETS: 0,5,7 */
layout(location = 0) out vec3 sceneColor;
layout(location = 1) out vec4 fogScattering;
layout(location = 2) out vec3 fogTransmittance;


#include "/lib/head.glsl"
#include "/lib/util/encoders.glsl"

const bool shadowHardwareFiltering = true;

in vec2 uv;

flat in mat3 colorPalette;

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

uniform sampler2DShadow shadowtex0;
uniform sampler2DShadow shadowtex1;
uniform sampler2D shadowcolor0;

uniform int frameCounter;
uniform int isEyeInWater;
uniform int worldTime;

uniform float eyeAltitude;
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

    vec3 transmittance = expf(-waterAttenCoeff * density);

    const vec3 scatterCoeff = vec3(5e-2, 1e-1, 2e-1);

    vec3 scatter    = 1.0-exp(-density * scatterCoeff);
        scatter    *= max(expf(-waterAttenCoeff * density), expf(-waterAttenCoeff * tau));

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

const vec3 airRayleighCoeff     = vec3(5.47e-6, 3.28e-6, 7.62e-6);
const vec3 airMieCoeff          = vec3(2e-5);    //19e-5 for rain

const mat2x3 airScatterMat      = mat2x3(airRayleighCoeff, airMieCoeff);
const mat2x3 airExtinctMat      = mat2x3(airRayleighCoeff, airMieCoeff);

const vec3 fogMistCoeff         = vec3(9e-3);
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

#define fogMistAltitude 144.0
#define airDensity 1.0

#ifdef volumeWorldTimeAnim
    float fogTime     = worldAnimTime * 3.6;
#else
    float fogTime     = frameTimeCounter * 0.006;
#endif

float mistDensity(vec3 rPos, float altitude) {
    vec3 wind   = vec3(fogTime, 0.0, fogTime * 0.5);
    float noise = value3D(rPos * 0.037 + wind) + value3D(rPos * 0.08 + wind * 3.0) * 0.5;

    float mist  = expf(-max0((altitude - 72.0) * 0.01));
        mist    = sstep(noise * rcp(1.5) - (1.0 - mist) * 0.5, 0.33, 0.6);
        mist   *= sqr(1.0 - linStep(altitude, 128.0, fogMistAltitude));

    return mist;
}

vec3 fogAirDensity(vec3 rPos, float altitude, bool terrain) {
    //float dist  = length(rPos);
    rPos   += cameraPosition;

    float maxFade = sqr(1.0 - linStep(altitude, 144.0, 256.0));

    vec2 rm     = expf(-max0((altitude - 66.0) * fogFalloffScale));
    //rm.y *= 0;
    float mist  = 0.0;
    mist = mistDensity(rPos, altitude);
    //if (terrain) rm *= 1.0 + sstep(dist, far * 0.6, far) * pi * 50.0;

    return vec3(rm * fogAirScale * maxFade * fogDensityMult, mist);
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

    float endDist   = isSky ? min(volumeHull, fogClipDist) : length(scenePos);
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

    vec3 sunlight       = colorPalette[0];
    vec3 skylight       = colorPalette[1];
    float pFade         = saturate(mieHG(vDotL, 0.65));

    uint i = 0;
    do {
        rPos += rStep; shadowPos += shadowStep;
    //for (uint i = 0; i < steps; ++i, rPos += rStep, shadowPos += shadowStep) {
        if (maxOf(transmittance) < 0.01) break;

        float altitude  = rPos.y + eyeAltitude;

        if (altitude > 256.0) continue;

        vec3 density    = fogAirDensity(rPos, altitude, !isSky);

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

mat2x3 unpackReflectionAux(vec4 data){
    vec3 shadows    = decodeRGBE8(vec4(unpack2x8(data.x), unpack2x8(data.y)));
    vec3 albedo     = decodeRGBE8(vec4(unpack2x8(data.z), unpack2x8(data.w)));

    return mat2x3(shadows, albedo);
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

    vec3 skyColor       = texture(colortex4, projectSky(worldDir, 0)).rgb;

    mat2x3 reflectionAux = unpackReflectionAux(texture(colortex3, uv));

    vec3 translucencyAbsorption = reflectionAux[1];

    float vDotL     = dot(normalize(position1), lightDirView);

    float caveMult  = linStep(eyeBrightnessSmooth.y/240.0, 0.1, 0.9);
    vec3 fogScatterColor = colorPalette[0] * mieHG(vDotL, 0.68) * sqrt(caveMult);
        fogScatterColor *= mix(0.33, 0.66, sqrt(abs(lightDir.y)));
        fogScatterColor += colorPalette[1] * rpi * caveMult;

    if (matID == 102 && isEyeInWater == 0) {
        #ifdef waterFogEnabled
        sceneColor = getWaterFog(sceneColor, distance(position0, position1), fogScatterColor);
        translucencyAbsorption  = vec3(1);
        #endif
    } else if (landMask(sceneDepth.y)) {
        #ifdef fogEnabled
        sceneColor  = getFog(sceneColor, distance(position0, position1), skyColor, worldDir);
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

    //sceneColor.rgb = stex(colortex10).rgb;
}