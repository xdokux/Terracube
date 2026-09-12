
#define COLORED_SHADOWS
#define SOFT_SHADOWS
#define SHADOW_SAMPLES 2 //[1 2 3 4 5 6]

uniform sampler2D noisetex;
uniform sampler2D shadowcolor0;
uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;

const int ShadowSamplesPerSize = 6 * SHADOW_SAMPLES + 1;
const int TotalSamples = ShadowSamplesPerSize * ShadowSamplesPerSize;

float GetShadow() {
#ifdef SOFT_SHADOWS
    float RandomAngle = texture2D(noisetex, texcoord * 20.0).r * 100.0;
    float cosTheta = cos(RandomAngle);
    float sinTheta = sin(RandomAngle);
    mat2 Rotation =  mat2(cosTheta, -sinTheta, sinTheta, cosTheta) / shadowMapResolution;
    float ShadowAccum = 0.0;
    for(int x = -SHADOW_SAMPLES; x <= SHADOW_SAMPLES; x++){
        for(int y = -SHADOW_SAMPLES; y <= SHADOW_SAMPLES; y++){
            vec2 Offset = Rotation * vec2(x, y);
            ShadowAccum += step(texture2D(shadowtex1, shadowPos.xy + Offset).r, shadowPos.z);
        }
    }
    ShadowAccum /= TotalSamples;
#else
    float ShadowAccum = step(texture2D(shadowtex1, shadowPos.xy).r, shadowPos.z);
#endif

    return ShadowAccum;
}