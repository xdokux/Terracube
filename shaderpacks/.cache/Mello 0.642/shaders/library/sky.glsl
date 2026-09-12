#define CLOUD_SAMPLES 3 // [1 2 3 4 5 6 7 8 9 10 20]
#define CLOUD_LIGHT_SAMPLES 5 // [1 2 3 4 5 6 7 8 9 10 20]
#define TAA 1 // [0 1]

uniform mat4 gbufferModelView;
uniform vec3 sunPosition;
uniform float rainStrength;

uniform sampler2D cloudTex;
uniform vec3 cameraPosition;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform float cloudTime;

vec3 calculateSkyGradient(vec3 viewDir) {
    float upDot = dot(viewDir, normalize(gbufferModelView[1].xyz));

    float baseT = clamp(upDot * 0.5 + 0.5, 0.0, 1.0);
    vec3 base = mix(getSkyMiddleColor(), getSkyTopColor(), baseT);

    float u = (upDot < -0.02) ? 0.0 : max(upDot, 0.0);
    float fogFactor = 0.025 / (u * u + 0.025);

    return mix(base, (getSkyHorizonColor() * pow(1.0 - rainStrength * 0.3, 2.0)), fogFactor) * (1.0 - rainStrength * 0.3);
}

vec3 calculateMie(vec3 viewDir){
    vec3 sunDir = normalize(sunPosition);

    float mu = abs(dot(viewDir, sunDir));
    float glow = pow(mu, mix(16.0, 8.0, rainStrength)) * 0.75 + pow(mu, mix(128.0, 32.0, rainStrength));
    glow *= 0.2;

    return getPointMieColor() * glow * (1.5 - rainStrength);
}

const float cloudBottom = 188.0;
const float cloudTop = 198.0;
const float cloudExtinction = 0.3;

float sampleCloudDensity(vec3 p) {
    vec2 uv = p.xz * 0.0003;
    uv.x += cloudTime * 0.001;
    float base = texture(cloudTex, uv).a;

    float h = clamp((p.y - cloudBottom) / (cloudTop - cloudBottom), 0.0, 1.0);
    float vertical = smoothstep(0.0, 0.15, h) * smoothstep(1.0, 0.55, h);

    return base * vertical;
}

float lightMarch(vec3 p, vec3 lightDir, float noise) {
    const int LIGHT_STEPS = CLOUD_LIGHT_SAMPLES;
    const float lightMarchDistance = 20.0;
    const float lightStepSize = lightMarchDistance / float(LIGHT_STEPS);

    float depth = 0.0;
    for (int j = 0; j < LIGHT_STEPS; j++) {
        vec3 lp = p + lightDir * (float(j) + noise) * lightStepSize;
        depth += sampleCloudDensity(lp) * lightStepSize;
    }
    return depth;
}

vec4 calculateClouds(vec3 viewDir, float noise, vec3 viewSpaceSunPos, vec3 rayOrigin, float maxDist) {
    vec4 cloud = vec4(0.0);

    const int VIEW_STEPS = CLOUD_SAMPLES;
    const float fogDensity = 0.0005;
    const float fogExponent = 2.0;
    const float maxFogDist = 60000.0;

    vec3 worldLightDir = normalize(mat3(gbufferModelViewInverse) * viewSpaceSunPos);
    if (worldLightDir.y < 0.0) worldLightDir = -worldLightDir;

    float cosTheta = dot(viewDir, worldLightDir);
    float miePhase = 0.5 + 0.5 * pow(max(0.0, cosTheta), 8.0);

    float tBottom = (cloudBottom - rayOrigin.y) / viewDir.y;
    float tTop = (cloudTop - rayOrigin.y) / viewDir.y;
    float tNear = min(tBottom, tTop);
    float tFar = max(tBottom, tTop);

    tNear = max(tNear, 0.0);
    tFar = min(tFar, min(maxDist, maxFogDist));
    if (tNear >= tFar) return cloud;

    float stepSize = (tFar - tNear) / float(VIEW_STEPS);
    float t = tNear + stepSize * noise;

    float mu = abs(cosTheta);
    float cloudGlow = pow(mu, mix(16.0, 8.0, rainStrength)) * 0.75 + pow(mu, mix(128.0, 32.0, rainStrength));
    cloudGlow *= 0.5;
    vec3 cloudMie = getPointMieColor() * cloudGlow * (1.5 - rainStrength);

    for (int i = 0; i < VIEW_STEPS; i++) {
        if (cloud.a > 0.995) break;

        vec3 p = rayOrigin + viewDir * t;
        float density = sampleCloudDensity(p);

        if (density > 0.001) {
            float stepAlpha = 1.0 - exp(-density * stepSize * cloudExtinction);

            float opticalDepth = lightMarch(p, worldLightDir, fract(noise + float(i) * 0.6180339887));
            
            float shadowFactor = 0.0;
            float atten = 1.0;
            float extinctionScale = 1.0;
            const int SCATTER_OCTAVES = 8;

            for (int k = 0; k < SCATTER_OCTAVES; k++) {
                shadowFactor += atten * exp(-opticalDepth * cloudExtinction * extinctionScale);
                atten *= 0.5;
                extinctionScale *= 0.5;
            }

            vec3 cloudColor =
                ((getSkyLightColor() * (1.0 - rainStrength * 0.3))
                + (getPointLightColor() * mix(0.25, 1.0, 1.0 - rainStrength)) * shadowFactor)
                + cloudMie;

            float dist = t;
            float fogFactor = 1.0 - exp(-pow(dist * fogDensity, fogExponent));
            float fadedAlpha = stepAlpha * (1.0 - fogFactor);

            cloud.rgb += (1.0 - cloud.a) * fadedAlpha * cloudColor;
            cloud.a   += (1.0 - cloud.a) * fadedAlpha;
        }

        t += stepSize;
    }

    return cloud;
}