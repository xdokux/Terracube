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
layout(location = 1) out vec4 bloomTiles;
layout(location = 2) out vec4 clear7;


#include "/lib/head.glsl"
#include "/lib/util/colorspace.glsl"
#include "/lib/util/encoders.glsl"

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

/* ------ FOG ------ */
#include "/lib/offset/gauss.glsl"

ivec2 clampTexelPos(ivec2 pos) {
    return clamp(pos, ivec2(0.0), ivec2(viewSize));
}

mat2x3 sampleFogSpatial(vec2 coord, const float LOD) {
    ivec2 pixelCoordUnscaled = ivec2(coord * viewSize);

    vec2 newCoord       = coord / LOD;
    ivec2 pixelCoord    = ivec2(newCoord * viewSize);

    ivec2 pos           = ivec2(coord * viewSize);

    vec3 centerScatter  = texelFetch(colortex5, pixelCoord, 0).rgb;
    vec3 centerTransmittance = texelFetch(colortex7, pixelCoord, 0).rgb;

    float centerDepth   = depthLinear(texelFetch(depthtex0, pixelCoordUnscaled, 0).x) * far;

    float totalWeight   = 1.0;
    vec3 totalScatter   = centerScatter * totalWeight;
    vec3 totalTrans     = centerTransmittance * totalWeight;

    for (int i = 0; i<9; i++) {
        ivec2 deltaPos      = kernelO_3x3[i] * 2;
        if (i == 4) continue;

        ivec2 samplePos     = pixelCoordUnscaled + deltaPos;
        ivec2 samplePosScaled = ivec2(vec2(samplePos) / LOD);

        bool valid          = all(greaterThanEqual(samplePos, ivec2(0))) && all(lessThan(samplePos, ivec2(viewSize)));

        if (!valid) continue;

        vec3 currentScatter = texelFetch(colortex5, clampTexelPos(samplePosScaled), 0).rgb;
        vec3 currentTrans   = texelFetch(colortex7, clampTexelPos(samplePosScaled), 0).rgb;
        float currentDepth  = depthLinear(texelFetch(depthtex0, samplePos, 0).x) * far;

        float depthDelta    = abs(currentDepth - centerDepth) * 48.0;

        float weight        = exp(-depthDelta);

        //accumulate stuff
        totalScatter   += currentScatter * weight;
        totalTrans     += currentTrans * weight;

        totalWeight    += weight;
    }

    totalScatter   /= max(totalWeight, 1e-16);
    totalTrans     /= max(totalWeight, 1e-16);

    return mat2x3(totalScatter, totalTrans);
}

void applyFogData(inout vec3 color, in mat2x3 data) {
    color = color * data[1] + data[0];
}


/* ------ Reflections ------ */
#include "/lib/frag/reflection.glsl"

void main() {
    sceneColor  = texture(colortex0, uv).rgb;

    vec4 GBuffer0       = texture(colortex1, uv);

    vec4 GBuffer1       = texture(colortex2, uv);
    int matID           = int(unpack2x8(GBuffer1.y).x * 255.0);

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
        reflectionAux[1] = saturate(reflectionAux[1]);
    
    #ifdef reflectionsEnabled
    if (landMask(sceneDepth.x)) {
        vec3 sceneNormal = decodeNormal(GBuffer0.xy);
        vec3 viewNormal = mat3(gbufferModelView) * sceneNormal;

        vec3 viewDir    = normalize(position0);

        float lightmap  = saturate(unpack2x8(GBuffer0.z).y);

        bool water      = matID == 102;

            reflectionAux[0] *= pi;

        vec3 directCol  = colorPalette[0];
            reflectionAux[0] = min(reflectionAux[0], directCol);

        materialProperties material = materialProperties(1.0, 0.02, false, false, mat2x3(0.0));
        if (water) material = materialProperties(0.01, 0.02, false, false, mat2x3(0.0));
        else material   = decodeLabBasic(unpack2x8(GBuffer1.x));

        if (dot(viewDir, viewNormal) > 0.0) viewNormal = -viewNormal;

        vec3 reflectDir = reflect(viewDir, viewNormal);
        
        vec4 reflection = vec4(0.0);
        vec3 fresnel    = vec3(0.0);

        float skyOcclusion  = cubeSmooth(sqr(linStep(lightmap, skyOcclusionThreshold - 0.2, skyOcclusionThreshold)));

        #ifdef resourcepackReflectionsEnabled
            // --- ROUGH REFLECTIONS --- //

            float roughnessFalloff  = 1.0 - (linStep(material.roughness, roughnessThreshold * 0.71, roughnessThreshold));

            #ifdef roughReflectionsEnabled
            if (material.roughness < 0.0002 || water) {
            #endif

                vec3 reflectSceneDir = mat3(gbufferModelViewInverse) * reflectDir;

                #ifdef screenspaceReflectionsEnabled
                    vec3 reflectedPos = screenspaceRT(position0, reflectDir, ditherBluenoise());
                    if (reflectedPos.z < 1.0) reflection += vec4(texelFetch(colortex0, ivec2(reflectedPos.xy * viewSize * ResolutionScale), 0).rgb, 1.0);
                    else reflection += readSpherePositionAware(skyOcclusion, scenePos[0], reflectSceneDir);
                #else
                    reflection += readSpherePositionAware(skyOcclusion, scenePos[0], reflectSceneDir);
                #endif

                    if (clamp16F(reflection) != reflection) reflection = vec4(0.0);

                    fresnel    += BRDFfresnelAlbedoTint(-viewDir, viewNormal, material, reflectionAux[1]);

            #ifdef roughReflectionsEnabled

            } else {
                mat3 rot        = getRotationMat(vec3(0, 0, 1), viewNormal);
                vec3 tangentV   = viewDir * rot;
                float noise     = ditherBluenoise();
                float dither    = ditherGradNoiseTemporal();

                const uint steps    = roughReflectionSamples;
                const float rSteps  = 1.0 / float(steps);

                for (uint i = 0; i < steps; ++i) {
                    if (roughnessFalloff <= 1e-3) break;
                    vec2 xy         = vec2(fract((i + noise) * sqr(32.0) * phi), (i + noise) * rSteps);
                    vec3 roughNrm   = rot * ggxFacetDist(-tangentV, material.roughness, xy);

                    vec3 reflectDir = reflect(viewDir, roughNrm);

                    vec3 reflectSceneDir = mat3(gbufferModelViewInverse) * reflectDir;

                    #ifdef screenspaceReflectionsEnabled
                        vec3 reflectedPos       = vec3(1.1);
                        if (material.roughness < 0.3) reflectedPos = screenspaceRT(position0, reflectDir, dither);
                        else if (material.roughness < 0.7) reflectedPos = screenspaceRT_LR(position0, reflectDir, dither);

                        if (reflectedPos.z < 1.0) reflection += vec4(texelFetch(colortex0, ivec2(reflectedPos.xy * viewSize * ResolutionScale), 0).rgb, 1.0);
                        else reflection += readSpherePositionAware(skyOcclusion, scenePos[0], reflectSceneDir);
                    #else
                        reflection += readSpherePositionAware(skyOcclusion, scenePos[0], reflectSceneDir);
                    #endif

                        fresnel    += BRDFfresnelAlbedoTint(-viewDir, roughNrm, material, reflectionAux[1]);
                }
                if (clamp16F(reflection) != reflection) reflection = vec4(0.0);

                reflection *= rSteps;
                fresnel    *= rSteps;

                reflection.a *= roughnessFalloff;
            }

            #else
                reflection.a *= roughnessFalloff;
            #endif

            if (material.conductor) sceneColor.rgb = mix(sceneColor.rgb, reflection.rgb * fresnel, reflection.a);
            else sceneColor.rgb = mix(sceneColor.rgb, reflection.rgb, fresnel * reflection.a);   

            //sceneColor.rgb = reflection.rgb;         
        #else
            // --- WATER REFLECTIONS --- //
            if (water) {
                vec3 reflectSceneDir = mat3(gbufferModelViewInverse) * reflectDir;

                #ifdef screenspaceReflectionsEnabled
                    vec3 reflectedPos = screenspaceRT(position0, reflectDir, ditherBluenoise());
                    if (reflectedPos.z < 1.0) reflection += vec4(texelFetch(colortex0, ivec2(reflectedPos.xy * viewSize * ResolutionScale), 0).rgb, 1.0);
                    else reflection += readSpherePositionAware(skyOcclusion, scenePos[0], reflectSceneDir);
                #else
                    reflection += readSpherePositionAware(skyOcclusion, scenePos[0], reflectSceneDir);
                #endif

                    if (clamp16F(reflection) != reflection) reflection = vec4(0.0);

                    fresnel    += BRDFfresnel(-viewDir, viewNormal, material, reflectionAux[1]);
                sceneColor.rgb = mix(sceneColor.rgb, reflection.rgb, fresnel * reflection.a);
            }   
        #endif

        #ifdef specularHighlightsEnabled
        sceneColor.rgb += specularTrowbridgeReitzGGX(-viewDir, lightDirView, viewNormal, material, reflectionAux[1]) * reflectionAux[0];
        #endif
    }
    #endif
    

    #ifdef fogEnabled
        if (isEyeInWater == 0 && landMask(sceneDepth.x)) sceneColor  = getFog(sceneColor, length(position0), skyColor, worldDir);
    #endif

    #ifdef waterFogEnabled
    if (isEyeInWater == 1) sceneColor = getWaterFog(sceneColor, length(position0), vec3(1));
    #endif

    #ifdef fogVolumeEnabled
        #ifdef fogSmoothingEnabled
            mat2x3 fogData      = sampleFogSpatial(uv, 1.0);
        #else
            mat2x3 fogData      = mat2x3(texture(colortex5, uv).rgb, texture(colortex7, uv).rgb);
        #endif

        applyFogData(sceneColor, fogData);
    #endif

    bloomTiles = vec4(0, 0, 0, 1);
    clear7  = vec4(0);
}