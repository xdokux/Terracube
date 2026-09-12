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

#include "/lib/head.glsl"

out vec2 uv;

out float skyOcclusion;

out float warp;

out vec3 scenePos;
out vec3 worldPos;

out vec4 tint;

flat out int matID;

flat out vec3 normal;

uniform mat4 gbufferModelView, gbufferModelViewInverse;
uniform mat4 shadowModelView, shadowModelViewInverse;

#include "/lib/light/warp.glsl"

uniform vec3 cameraPosition;

attribute vec4 mc_Entity;
attribute vec4 mc_midTexCoord;

#ifdef windEffectsEnabled
    #include "/lib/vertex/wind.glsl"

    float waterVertexWaves(vec3 pos, const float size) {
        vec3 p  = pos * size;

        float t = frameTimeCounter * pi * 0.5;
        vec3 w  = vec3(t*0.9, t*0.2, t*0.3);

        float wave  = value3D(p + w);
            p.xz    = rotatePosXY(p.xz, 0.4 * pi);
            wave   += value3D(p * 2.0 + w) * 0.5;
            wave   -= 0.75;

        return wave*0.2;
    }
#endif

#define WIND_NEW_TOPVERT

attribute vec3 at_midBlock;

bool getFoliageTopVertex(float worldY) {
    #ifdef WIND_NEW_TOPVERT
    float bottomY = (worldY + (at_midBlock.y / 64.0)) - 0.45;

    return worldY > bottomY;
    #else
    return (gl_MultiTexCoord0.t < mc_midTexCoord.t);
    #endif
}


void main() {
    uv    = (gl_TextureMatrix[0]*gl_MultiTexCoord0).xy;

    tint        = gl_Color;

    normal      = normalize(gl_NormalMatrix*gl_Normal);

    vec4 pos    = gl_Vertex;
        pos     = gl_ModelViewMatrix * pos;

        pos.xyz = transMAD(shadowModelViewInverse, pos.xyz);

        scenePos   = pos.xyz;
        worldPos   = pos.xyz+cameraPosition;

    float slmap  = linStep((gl_TextureMatrix[1]*gl_MultiTexCoord1).y, rcp(16.0), 1.0);

    skyOcclusion    = slmap;

    #ifdef windEffectsEnabled
        bool windLod    = length(pos.xz) < 64.0;

        if (windLod) {
            bool topVertex    = getFoliageTopVertex(pos.y);

            float occlude   = sqr(slmap)*0.9+0.1;

            if ((mc_Entity.x >= 10021 && mc_Entity.x <=10024) || mc_Entity.x == 10027) {
                vec2 windOffset = vertexWindEffect(pos.xyz + cameraPosition, 0.18, 1.0);

                if (mc_Entity.x == 10027) pos.xz += windOffset.xy * (1.0 + length(windOffset));
                    windOffset*= occlude;

                if (mc_Entity.x == 10021) pos.xyz += windOffset.xyy*0.4;

                if (mc_Entity.x == 10022 && topVertex)
                    pos.xz += windOffset;

                if ((mc_Entity.x == 10023 && topVertex) || (mc_Entity.x == 10024)) pos.xz += windOffset * 0.5;
                if ((mc_Entity.x == 10024 && topVertex)) pos.xz += windOffset * 0.5;
            }
        }
    #endif

        pos.xyz = transMAD(shadowModelView, pos.xyz);

        pos     = gl_ProjectionMatrix * pos;

        pos.xy  = shadowmapWarp(pos.xy, warp);
        pos.z  *= 0.2;

    gl_Position = pos;

    //mat ids
    if (mc_Entity.x == 10001) matID = 102;
    else if (mc_Entity.x == 10003) matID = 103;
    else matID = 1;
}