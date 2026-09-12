#version 330 compatibility

uniform sampler2D colortex0;
uniform sampler2D depthtex0;

uniform float viewHeight;
uniform float viewWidth;

uniform mat4 gbufferModelView;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferProjection;

uniform vec3 shadowLightPosition;

uniform vec3 endFlashPosition;
uniform float endFlashIntensity;

const float sunPathRotation = 30.0;

layout(location = 0) out vec4 color;

in vec2 texcoord;

vec3 calculateSkyGradient(vec3 viewDir) {
    float upDot = dot(viewDir, normalize(gbufferModelView[1].xyz));

    float baseT = clamp(upDot * 0.5 + 0.5, 0.0, 1.0);
    vec3 base = mix(vec3(0.05, 0.0, 0.1), vec3(0.0, 0.0, 0.1), baseT);

    float u = (upDot < -0.02) ? 0.0 : max(upDot, 0.0);
    float fogFactor = 0.025 / (u * u + 0.025);

    return mix(base, vec3(0.1, 0.01, 0.2), fogFactor);
}

vec3 calculateMie(vec3 viewDir, vec3 sunDir){
    float mu = max(dot(viewDir, sunDir), 0.0);
    float phase = pow(mu, 32.0);
    return vec3(1.0, 0.5, 0.5) * phase;
}

vec3 calculateEndFlash(vec3 viewDir){
    vec3 flashDir = normalize(endFlashPosition);

    float mu = max(dot(viewDir, flashDir), 0.0);
    float glow = pow(mu, 2048.0) * endFlashIntensity * 2.5;
    glow += pow(mu, 512.0) * endFlashIntensity * 0.3;
    glow += pow(mu, 32.0) * endFlashIntensity * 0.05;

    return vec3(1.0, 0.2, 1.0) * glow * 2.0;
}

void main() {
    color = texture(colortex0, texcoord);
    float depth = texture(depthtex0, texcoord).r;
    if (depth != 1.0) return;

    vec2 screenUV = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
    vec4 ndcPos = vec4(screenUV, 1.0, 1.0) * 2.0 - 1.0;
    vec4 tmp = gbufferProjectionInverse * ndcPos;
    vec3 viewDir = normalize(tmp.xyz / tmp.w);

    vec3 sunDir = normalize(shadowLightPosition);

    vec3 skyColor = calculateSkyGradient(viewDir);
    vec3 skyMie = calculateMie(viewDir, sunDir);
    vec3 skyFlash = calculateEndFlash(viewDir);

    vec3 sky = skyColor + skyMie + skyFlash;

    color = vec4(sky, 0.0);
}