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
uniform vec2 viewSize;
#define VERTEX_STAGE
#include "/lib/downscaleTransform.glsl"

out mat2x2 uv;

out vec4 tint;

flat out vec3 normal;

uniform vec2 taaOffset;

uniform mat4 gbufferModelView, gbufferModelViewInverse;

attribute vec4 mc_midTexCoord;

#ifdef gTERRAIN
    flat out int foliage;

    flat out int matID;
    flat out int emissionID;

    out vec3 worldPos;

    uniform vec3 cameraPosition;

    attribute vec4 mc_Entity;

    #ifdef windEffectsEnabled
        #include "/lib/vertex/wind.glsl"
    #endif
#else
    flat out int emitter;
#endif

#ifdef gTEXTURED
    #if (defined normalmapEnabled || defined pomEnabled)
        //flat out int validAtTangent;

        flat out mat3 tbn;

        attribute vec4 at_tangent;
    #endif

    #if (MC_VERSION >= 11500 && (defined gBLOCK || defined gENTITY || defined gHAND) && defined vertexAttributeFix)
        #define tbnFix
    #endif

    out float vertexDist;
    out vec2 vCoord;
    out vec4 vCoordAM;
    out vec3 viewVec;

    #ifdef tbnFix
    out vec3 vertexPos;
    #endif
#endif

int remapEmissionID(int mcEntity) {     // Eight Bits
    int blockID     = 0;

    /* Albedo Tinted Emission */
    if (mcEntity == 1000) blockID = 1;  // Bright Block Emitters

    if (mcEntity == 1001
     || mcEntity == 10002) blockID = 2;  // Medium Block Emitters

    if (mcEntity == 1002) blockID = 3;  // Dim Block Emitters

    if (mcEntity == 1003) blockID = 4;  // Very Dim Block Emitters

    /* Hardcoded Emission Types */
    if (mcEntity == 1020) blockID = 10;  // Torch
    if (mcEntity == 1021) blockID = 11;  // Soul
    if (mcEntity == 1022) blockID = 12;  // Soul

    return blockID;
}

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
    uv[0]    = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    uv[1]    = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;

    #ifndef gTERRAIN
        emitter     = 0;
    #endif

    #if !(defined gTERRAIN || defined gENTITY) && defined gTEXTURED
        if (uv[1].x > (15.0 / 16.0)) emitter = 1;
    #endif

    uv[1].x  = linStep(uv[1].x, rcp(24.0), 1.0);
    uv[1].y  = linStep(uv[1].y, rcp(16.0), 1.0);

    vec4 pos    = gl_Vertex;
        pos     = transMAD(gl_ModelViewMatrix, pos.xyz).xyzz;
    
    #ifdef tbnFix
    vertexPos   = mat3(gbufferModelViewInverse) * pos.xyz;
    #endif

    vec3 viewNormal     = normalize(gl_NormalMatrix*gl_Normal);

    normal      = mat3(gbufferModelViewInverse) * viewNormal;

    #ifdef gTEXTURED

        #ifdef pomEnabled
            vec3 viewTangent = normalize(gl_NormalMatrix*at_tangent.xyz);
            vec3 viewBinormal = normalize(gl_NormalMatrix*cross(at_tangent.xyz, gl_Normal.xyz) * at_tangent.w);

            mat3 viewtbn = mat3(viewTangent.x, viewBinormal.x, viewNormal.x,
                    viewTangent.y, viewBinormal.y, viewNormal.y,
                    viewTangent.z, viewBinormal.z, viewNormal.z);

            vec2 coordMid   = (gl_TextureMatrix[0] * mc_midTexCoord).xy;
            vec2 coordNMid  = uv[0] - coordMid;

            vCoordAM.zw     = abs(coordNMid) * 2.0;
            vCoordAM.xy     = min(uv[0], coordMid - coordNMid);

            vCoord          = sign(coordNMid) * 0.5 + 0.5;
            viewVec         = viewtbn * (gl_ModelViewMatrix * gl_Vertex).xyz;
            vertexDist      = length(pos.xyz);
        #elif defined normalmapEnabled
            vec3 viewTangent = normalize(gl_NormalMatrix*at_tangent.xyz);
            vec3 viewBinormal = normalize(gl_NormalMatrix*cross(at_tangent.xyz, gl_Normal.xyz) * at_tangent.w);
        #endif

        #ifdef normalmapEnabled
            vec3 tangent = mat3(gbufferModelViewInverse) * viewTangent;
            vec3 binormal = mat3(gbufferModelViewInverse) * viewBinormal;

            tbn     = mat3(tangent.x, binormal.x, normal.x,
                        tangent.y, binormal.y, normal.y,
                        tangent.z, binormal.z, normal.z);
        #endif
    #endif

    tint        = gl_Color;

    #ifdef gTERRAIN
        worldPos = transMAD(gbufferModelViewInverse, pos.xyz) + cameraPosition;
    #endif

    #if (defined gTERRAIN && defined windEffectsEnabled)
        pos.xyz = transMAD(gbufferModelViewInverse, pos.xyz);

        bool windLod    = length(pos.xz) < 192.0;
        
        if (windLod) {
            bool topVertex    = getFoliageTopVertex(pos.y);

            float occlude   = sqr(uv[1].y)*0.9+0.1;

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

        pos.xyz = transMAD(gbufferModelView, pos.xyz);
    #endif

        pos     = pos.xyzz * diag4(gl_ProjectionMatrix) + vec4(0.0, 0.0, gl_ProjectionMatrix[3].z, 0.0);

    #ifdef taaEnabled
        pos.xy += taaOffset * pos.w / ResolutionScale;
    #endif
        
    gl_Position = pos;
    VertexDownscaling(gl_Position);

    #ifdef gTERRAIN
        matID  = 1;

        if (
         mc_Entity.x == 10022 ||
         mc_Entity.x == 10023 ||
         mc_Entity.x == 10024 ||
         mc_Entity.x == 10025 ||
         mc_Entity.x == 10027 ||
         mc_Entity.x == 10202) matID = 2;

        if (
         mc_Entity.x == 10021 ||
         mc_Entity.x == 10026) matID = 4;

        if (mc_Entity.x == 10301 ||
         mc_Entity.x == 10002) matID = 5;

        if (mc_Entity.x == 10302) matID = 6;

        emissionID = remapEmissionID(int(mc_Entity.x));
        //if (emissionID == 0 && emitter) emissionID = 2;
    #endif
}