#ifndef VOXY_TERRAIN
    uniform float viewWidth;
    uniform float viewHeight;
    uniform float aspectRatio;
    uniform int isEyeInWater;
    uniform float frameTime;
    uniform float frameTimeCounter;
    uniform vec3 fogColor;
    uniform vec3 cameraPosition;
    uniform vec3 cameraPositionFract;
    uniform vec4 entityColor;
    uniform int worldTime;
    uniform float rainStrength;
    uniform float thunderStrength;
    uniform float temperature;
    uniform vec3 sunPosition;
    uniform vec3 moonPosition;
    uniform int worldDay;
    uniform int heldBlockLightValue;
    uniform int heldBlockLightValue2;
    uniform float darknessFactor;
    uniform float darknessLightFactor;
    uniform float blindness;
    uniform ivec2 eyeBrightnessSmooth;
    uniform vec3 upPosition;
    uniform vec3 previousCameraPosition;
    uniform vec3 previouscameraPositionFract;
    uniform int frameCounter;
    uniform vec3 shadowLightPosition;
    uniform float sunAngle;
    uniform int renderStage;
    uniform int entityId;
    uniform ivec2 atlasSize;
    uniform vec4 lightningBoltPosition;
    uniform float wetness;

    uniform sampler2D colortex0;
    uniform sampler2D colortex1;
    uniform sampler2D colortex2;
    uniform sampler2D colortex3;
    uniform sampler2D colortex4;
    uniform sampler2D colortex5;
    uniform sampler2D colortex6;
    uniform sampler2D colortex7;
    uniform sampler2D colortex8;
    uniform sampler2D colortex9;
    uniform sampler2D colortex10;
    uniform sampler2D colortex11;
    uniform sampler2D shadowtex0;
    uniform sampler2D shadowtex1;
    uniform sampler2D shadowcolor0;
    uniform sampler2D shadowcolor1;
    uniform sampler2D shadowcolor2;
    uniform sampler2D gtexture;
    uniform sampler2D lightmap;
    uniform sampler2D depthtex0;
    uniform sampler2D depthtex1;
    uniform sampler2D noisetex;
    uniform sampler2D specular;
    uniform sampler2D normals;

    // Voxy exclusives
    uniform sampler2D colortex16;
    uniform sampler2D colortex17;
    uniform sampler2D colortex18;

    uniform mat4 gbufferProjectionInverse;
    uniform mat4 gbufferProjection;
    uniform mat4 gbufferModelView;
    uniform mat4 gbufferModelViewInverse;
    uniform mat4 gbufferPreviousModelView;
    uniform mat4 gbufferPreviousProjection;
    uniform mat4 shadowModelView;
    uniform mat4 shadowModelViewInverse;
    uniform mat4 shadowProjection;
    uniform mat4 shadowProjectionInverse;

    uniform float near;
    uniform float far;

    // Custom Uniforms
    uniform vec2 resolution;
    uniform vec2 resolutionInv;
    uniform vec2 taaJitter;
    uniform vec3 sunPosN;
    uniform vec3 sLightPosN;
    uniform float isOutdoorsSmooth;
    uniform float precipitationSmooth;

    // Weather related custom uniforms
    uniform float cloudStartOffset;
    uniform float cloudCoverageVl;
    uniform float cloudCoverageFlat;
    uniform float anisotropy;
    uniform float fogAmount;
    uniform float betaRfact;
    uniform vec2 windDirection;

    uniform sampler2D waterNoise;
    uniform sampler2D cloudNoise;
    uniform sampler2D blueNoiseTexture;
    uniform sampler2D image0Sampler;
    uniform sampler2D image1Sampler;
    uniform sampler2D image2Sampler;
    uniform sampler2D atm_transmittance_sampler;
    uniform sampler2D atm_skyview_sampler;
    uniform sampler2D atm_multi_scattering_sampler;
    uniform sampler3D worleyNoiseTexture;
    uniform sampler2D smaaAreaTexture;
    uniform sampler2D smaaSearchTexture;
    uniform sampler2D windTexture;
    uniform sampler2D milkyWay;

    uniform sampler2D vxDepthTexTrans;
    uniform sampler2D vxDepthTexOpaque;
    uniform mat4 vxProjInv;
    uniform mat4 vxProj;
    uniform mat4 vxProjPrev;
    uniform mat4 vxModelView;
    uniform mat4 vxModelViewInv;
    uniform mat4 vxModelViewPrev;
    uniform int vxRenderDistance;

    uniform sampler2DShadow shadowtex0HW;
    uniform sampler2DShadow shadowtex1HW;

    layout(std430, binding = 0) restrict buffer dataBuffer {
        vec3 SunColor;
        vec3 SunColorVlClouds;
        vec3 SunColorFlatClouds;
        vec3 MoonColorVlClouds;
        vec3 MoonColorFlatClouds;
        float DofFocus;
        vec3 MoonColor;
        float AvgLum;
        vec3 AmbientColor;
        float SunVisibility;
    } dataBuf;

    layout(std430, binding = 1) restrict buffer histogramBuffer {
        uint data[256];
    } histogramBuf;

    #ifdef VOXELISATION
        uniform sampler3D voxelImgSampler_a;
        uniform sampler3D voxelImgSampler_b;
    #endif
#endif

#ifdef VOXELISATION
    layout(rgba16) uniform restrict image3D voxelImg_a;
    layout(rgba16) uniform restrict image3D voxelImg_b;
#endif
layout(rgba16f) uniform restrict image2D image0;
layout(rg8) uniform restrict image2D image1;
layout(rgba16f) uniform restrict image2D image2;
layout(rgba8) uniform restrict image2D atm_transmittance;
layout(rgba8) uniform restrict image2D atm_skyview;
layout(rgba16f) uniform restrict image2D atm_multi_scattering;

#ifdef VOXY
    #define DISTANT_HORIZONS

    #define dhDepthTex0 vxDepthTexTrans
    #define dhDepthTex1 vxDepthTexOpaque

    #define dhProjectionInverse vxProjInv
    #define dhProjection vxProj
    #define dhPreviousProjection vxProjPrev
    
    #define dhRenderDistance (vxRenderDistance * 16)
#else
    uniform sampler2D dhDepthTex0;
    uniform sampler2D dhDepthTex1;

    uniform mat4 dhProjectionInverse;
    uniform mat4 dhProjection;
    uniform mat4 dhPreviousProjection;

    uniform int dhRenderDistance;
#endif

const bool colortex0Clear = false;
const bool colortex1Clear = false;
const bool colortex2Clear = false;
const bool colortex3Clear = false;
const bool colortex4Clear = false;
const bool colortex5Clear = false;
const bool colortex6Clear = false;
const bool colortex7Clear = false;
const bool colortex8Clear = false;
const bool colortex9Clear = false;
const bool colortex10Clear = true;
const bool colortex11Clear = false;
const bool shadowcolor0Clear = true;
const vec4 shadowcolor0ClearColor = vec4(0, 0, 0, 1);
const bool shadowcolor1Clear = true;
const bool shadowcolor2Clear = false;

const float PI = 3.141592653589793;
const float TAU = 2 * PI;
const float GOLDEN_RATIO = 1.61803398875;

const bool shadowHardwareFiltering = true;

const int noiseTextureResolution = 512;

const float SEA_LEVEL = 62.9;

const float CLOUD_TEX_SIZE = 128.0;

const float shadowDistanceRenderMul = 1.0;

#ifdef DISTANT_HORIZONS
    float shadowDistanceDH = far - 16 < shadowDistance ? far - 16 : shadowDistance;
#else
    float shadowDistanceDH = shadowDistance;
#endif

/*
const int colortex0Format = RGB16F;
const int colortex1Format = RGBA16;
const int colortex2Format = RGBA16;
const int colortex3Format = RGBA16F;
const int colortex4Format = RGBA8;
const int colortex5Format = RGBA8;
const int colortex6Format = RGBA16F;
const int colortex7Format = RGBA16F;
const int colortex8Format = R16;
const int colortex9Format = RGBA8;
const int colortex10Format = RGBA16F;
const int colortex11Format = RGBA16F;
const int colortex16Format = RGBA16F;
const int colortex17Format = RGBA16;
const int colortex18Format = RGBA16;
const int shadowcolor1Format = RG8;
const int shadowcolor2Format = R8;
*/
