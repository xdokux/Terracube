/*
    composite.fsh
    Reads: colortex0 (lit scene), depthtex0
    Writes: colortex0, with sky/clouds painted into any pixel whose
            depth is 1.0 (i.e. nothing was drawn there - vanilla sky)

    Doing sky procedurally here instead of overriding gbuffers_sky*
    keeps the pack to one place for all the atmosphere code, and is
    how most modern shaderpacks (BSL, Complementary) actually do it.
*/
#version 330 compatibility

#include "lib/settings.glsl"
#include "lib/common.glsl"
#include "lib/lighting.glsl"
#include "lib/sky.glsl"

uniform sampler2D colortex0;
uniform sampler2D depthtex0;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;
uniform float frameTimeCounter;

varying vec2 texCoord;

vec3 viewDirFromUV(vec2 uv) {
    vec4 clip = vec4(uv * 2.0 - 1.0, 1.0, 1.0);
    vec4 view = gbufferProjectionInverse * clip;
    view /= view.w;
    vec3 worldDir = mat3(gbufferModelViewInverse) * normalize(view.xyz);
    return normalize(worldDir);
}

void main() {
    vec3 color = texture2D(colortex0, texCoord).rgb;
    float depth = texture2D(depthtex0, texCoord).r;

    if (depth >= 0.9999) {
        vec3 viewDir = viewDirFromUV(texCoord);
        vec3 lightDir = getShadowLightDirection();
        float dayFactor = getDayFactor(lightDir);
        vec3 lightColor = getSunMoonColor(dayFactor);

        vec3 sky = skyGradient(viewDir, lightDir, lightColor, dayFactor);
        sky += sunMoonGlow(viewDir, lightDir, lightColor);

#if CLOUDS == 1
        float clouds = cloudDensity(viewDir, cameraPosition, frameTimeCounter);
        vec3 cloudColor = mix(vec3(0.35, 0.37, 0.42), lightColor * 0.9 + 0.3, dayFactor);
        sky = mix(sky, cloudColor, clouds * 0.85);
#endif

        color = sky;
    }

    gl_FragColor = vec4(color, 1.0);
}
