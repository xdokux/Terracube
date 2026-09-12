#version 120

//Distort
vec2 DistortPosition(in vec2 position){
    float CenterDistance = length(position);
    float DistortionFactor = mix(1.0f, CenterDistance, 0.9f);
    return position / DistortionFactor;
}

varying vec2 TexCoords;

// Direction of the sun (not normalized!)
uniform vec3 sunPosition;

// Textures
uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D depthtex0;
uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
uniform sampler2D shadowcolor0;
uniform sampler2D noisetex;

uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;

/* ================= SUN COLORS (REDUCTION) ================= */

// Sunrise
#define RLRISE  5.5
#define GLRISE  2.8
#define BLRISE  2.0

// Noon
#define RLDAY   1.86
#define GLDAY   1.86
#define BLDAY   2.00

// Sunset
#define RLSET   7.0
#define GLSET   3.5
#define BLSET   3.8

// Night
#define RLNIGHT 0.30
#define GLNIGHT 0.50
#define BLNIGHT 0.76

uniform int worldTime;
uniform int isEyeInWater;
uniform float frameTimeCounter;
float time = float(worldTime);

float Sunrise   = ((clamp(time, 23000.0, 23500.0) - 23000.0) / 500.0) + (1.0 - (clamp(time, 0.0, 4000.0) / 4000.0));
float Noon      = ((clamp(time, 0.0, 4000.0)) / 4000.0) - ((clamp(time, 8000.0, 12000.0) - 8000.0) / 4000.0);
float Sunset    = ((clamp(time, 8000.0, 12000.0) - 8000.0) / 4000.0) - ((clamp(time, 12000.0, 13800.0) - 12000.0) / 1800.0);
float Midnight  = 1.0 - Sunrise - Noon - Sunset;

/* ================= SHADOW CONFIG ================= */

#define SHADOW
#define SHADOW_SAMPLES 2
#define SHADOW_MAP_RESOLUTION 1024
#define SHADOW_TRANSPARENCY 1.4
#define SKY_EXPOSURE 2.0
#define LIGHTING_BRITHNESS 8

const float sunPathRotation = -30;
const int noiseTextureResolution = 2048;
const float Ambient = 0.000025f;

/* ================= LIGHTMAP ================= */

float AdjustLightmapTorch(in float torch) {
    return 2.0 * pow(torch, 5.06);
}

float AdjustLightmapSky(in float sky){
    float s = sky * sky;
    s *= SHADOW_TRANSPARENCY;
    return s * s;
}

vec2 AdjustLightmap(in vec2 lm){
    return vec2(
        AdjustLightmapTorch(lm.x),
        AdjustLightmapSky(lm.y)
    );
}

vec3 GetLightmapColor(in vec2 Lightmap){
    Lightmap = AdjustLightmap(Lightmap);

    const vec3 TorchColor = vec3(1.0, 0.6, 0.45);
    const vec3 SkyColor   = vec3(0.05, 0.15, 0.3);

    vec3 TorchLighting = Lightmap.x * TorchColor * LIGHTING_BRITHNESS;
    vec3 SkyLighting   = Lightmap.y * SkyColor;

    return TorchLighting + SkyLighting;
}

/* ================= SHADOWS ================= */

#ifdef SHADOW
float Visibility(in sampler2D sm, in vec3 sc) {
    return step(sc.z - 0.001, texture2D(sm, sc.xy).r);
}

vec3 TransparentShadow(in vec3 sc){
    float v0 = Visibility(shadowtex0, sc);
    float v1 = Visibility(shadowtex1, sc);
    vec4 c   = texture2D(shadowcolor0, sc.xy);
    vec3 t   = c.rgb * (1.0 - c.a);
    return mix(t * v1, vec3(1.0), v0);
}

vec3 GetShadow(float depth) {
    vec3 clip = vec3(TexCoords, depth) * 2.0 - 1.0;
    vec4 viewW = gbufferProjectionInverse * vec4(clip, 1.0);
    vec3 view = viewW.xyz / viewW.w;
    vec4 world = gbufferModelViewInverse * vec4(view, 1.0);
    vec4 shadow = shadowProjection * shadowModelView * world;

    shadow.xy = DistortPosition(shadow.xy);
    vec3 sc = shadow.xyz * 0.5 + 0.5;

    vec3 sum = vec3(0.0);
    for(int x=-2;x<=2;x++)
    for(int y=-2;y<=2;y++){
        sum += TransparentShadow(vec3(sc.xy + vec2(x,y)/SHADOW_MAP_RESOLUTION, sc.z));
    }
    return sum / 25.0;
}
#endif

/* ================= MAIN ================= */

void main(){
    vec2 uv = TexCoords;

    if(isEyeInWater == 1){
        float t = frameTimeCounter * 1.5;
        uv.x += sin(uv.y * 30.0 + t * 2.0) * 0.002;
        uv.y += cos(uv.x * 25.0 + t * 1.7) * 0.002;
        uv.x += sin(uv.y * 50.0 + t * 3.0) * 0.001;
        uv.y += cos(uv.x * 40.0 + t * 2.5) * 0.001;
    }

    vec3 lightColor =
        vec3(RLRISE,GLRISE,BLRISE) * Sunrise +
        vec3(RLDAY,GLDAY,BLDAY) * Noon +
        vec3(RLSET,GLSET,BLSET) * Sunset +
        vec3(RLNIGHT,GLNIGHT,BLNIGHT) * Midnight;

    vec3 Albedo = pow(texture2D(colortex0, uv).rgb, vec3(2.2));
    float Depth = texture2D(depthtex0, uv).r;

    if(Depth == 1.0){
        gl_FragData[0] = vec4(Albedo, 1.0);
        return;
    }

    vec3 Normal = normalize(texture2D(colortex1, uv).rgb * 2.0 - 2.0);
    vec2 Lightmap = texture2D(colortex2, uv).rg;

    float NdotL = max(dot(Normal, normalize(sunPosition)), 0.5);
    vec3 Diffuse;

    if(isEyeInWater == 1){
        vec3 underwaterLight = Albedo * (vec3(0.15, 0.35, 0.6) * lightColor + vec3(0.05, 0.12, 0.2));
        Diffuse = underwaterLight;
    } else {
        Diffuse = Albedo * (GetLightmapColor(Lightmap) + lightColor * NdotL * GetShadow(Depth) * SKY_EXPOSURE + Ambient);
    }

    // 🔻 GLOBAL RED REDUCTION (slightly stronger)
    Diffuse.r *= 0.75;

    gl_FragData[0] = vec4(Diffuse, 1.0);
}
