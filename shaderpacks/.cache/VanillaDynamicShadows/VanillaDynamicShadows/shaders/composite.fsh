/*
    composite.fsh
    This is the LAST stage in the pipeline (no final.* files) -
    keeping the pass count as low as possible, on purpose, for the
    UHD 630 target.

    God rays: for each pixel, march from the camera out to that
    pixel's actual depth, sampling shadow-map visibility along the
    way, and add light color proportional to how much of the ray was
    unoccluded. Because this is driven entirely by the shadow map
    (a world-space visibility test), NOT by the sun's position on
    screen, it produces visible shafts through gaps in geometry
    (tree canopies, cave mouths, window bars) regardless of whether
    the sun/moon disc itself is currently in frame - directly
    satisfying "godrays must be visible even if the light source
    isn't within my FOV".
*/
#version 330 compatibility

#include "lib/settings.glsl"
#include "lib/lighting.glsl"

uniform sampler2D colortex0;
uniform sampler2D depthtex0;
uniform sampler2DShadow shadowtex1;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowProjection;
uniform mat4 shadowModelView;
uniform float rainStrength;

varying vec2 texCoord;

vec3 viewPosFromDepth(vec2 uv, float depth) {
    vec4 clip = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 view = gbufferProjectionInverse * clip;
    return view.xyz / view.w;
}

// Fixed screen-space dither pattern (interleaved gradient noise) -
// NOT time-animated, so it doesn't introduce any flicker of its own;
// it only exists to hide banding between the low, fixed step count.
float ditherPattern(vec2 screenPos) {
    return fract(52.9829189 * fract(dot(screenPos, vec2(0.06711056, 0.00583715))));
}

void main() {
    vec3 color = texture2D(colortex0, texCoord).rgb;

#if GODRAYS == 1
    float depth = texture2D(depthtex0, texCoord).r;
    vec3 fragViewPos = viewPosFromDepth(texCoord, depth);

    vec3 lightDir = getShadowLightDirection();
    float dayFactor = getDayFactor(lightDir);

    // Sun/moon below horizon, or heavy rain: skip the raymarch
    // entirely rather than paying for a loop with nothing to show -
    // this is a real cost saving on the UHD 630, not a visual choice.
    if (lightDir.y > 0.02 && rainStrength < 0.9) {
        vec3 lightColor = getSunMoonColor(dayFactor);

        float marchDistance = min(length(fragViewPos), GODRAY_DISTANCE);
        vec3 rayDir = normalize(fragViewPos);
        float stepSize = marchDistance / float(GODRAY_STEPS);
        float dither = ditherPattern(gl_FragCoord.xy);

        float accumulated = 0.0;
        for (int i = 0; i < GODRAY_STEPS; i++) {
            float t = (float(i) + dither) * stepSize;
            vec3 samplePos = rayDir * t;
            vec4 worldPos = gbufferModelViewInverse * vec4(samplePos, 1.0);
            vec4 shadowClip = shadowProjection * (shadowModelView * worldPos);
            vec3 shadowScreen = shadowClip.xyz / shadowClip.w * 0.5 + 0.5;

            if (shadowScreen.x >= 0.0 && shadowScreen.x <= 1.0 &&
                shadowScreen.y >= 0.0 && shadowScreen.y <= 1.0 &&
                shadowScreen.z >= 0.0 && shadowScreen.z <= 1.0) {
                accumulated += texture(shadowtex1, vec3(shadowScreen.xy, shadowScreen.z - 0.0015));
            } else {
                accumulated += 1.0; // beyond shadow distance - treat as unoccluded
            }
        }
        accumulated /= float(GODRAY_STEPS);

        // Fade toward the horizon for a softer look, and keep overall
        // strength modest - GODRAY_INTENSITY defaults low specifically
        // because you asked for no "insane bloom"-style overdone glow.
        float intensity = accumulated * smoothstep(0.0, 0.25, lightDir.y) * GODRAY_INTENSITY;
        color += lightColor * intensity;
    }
#endif

    gl_FragColor = vec4(color, 1.0);
}
