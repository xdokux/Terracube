#ifndef CINDERLIGHT_OVERWORLD_WATER_REFLECTIONS_GLSL
#define CINDERLIGHT_OVERWORLD_WATER_REFLECTIONS_GLSL

// Lightweight, removable Overworld water reflections.
// This module never calls the wave shader. It consumes only the normal/depth
// metadata produced by gbuffers_water, so disabling this include leaves the
// standalone wave system fully functional.

#if WATER_QUALITY == 0
const int CINDERLIGHT_REFLECTION_STEPS = 4;
const float CINDERLIGHT_REFLECTION_DISTANCE = 38.0;
const float CINDERLIGHT_REFLECTION_STRENGTH = 0.25;
#elif WATER_QUALITY == 2
const int CINDERLIGHT_REFLECTION_STEPS = 8;
const float CINDERLIGHT_REFLECTION_DISTANCE = 68.0;
const float CINDERLIGHT_REFLECTION_STRENGTH = 0.34;
#else
const int CINDERLIGHT_REFLECTION_STEPS = 6;
const float CINDERLIGHT_REFLECTION_DISTANCE = 56.0;
const float CINDERLIGHT_REFLECTION_STRENGTH = 0.30;
#endif

vec3 cinderReconstructViewPosition(vec2 screenCoord, float depth) {
    vec4 clipPosition = vec4(screenCoord * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 viewPosition = gbufferProjectionInverse * clipPosition;
    return viewPosition.xyz / max(abs(viewPosition.w), 1.0e-5);
}

bool cinderProjectViewPosition(vec3 viewPosition, out vec2 screenCoord) {
    vec4 clipPosition = gbufferProjection * vec4(viewPosition, 1.0);
    if (clipPosition.w <= 0.0001) {
        screenCoord = vec2(-1.0);
        return false;
    }

    vec2 ndc = clipPosition.xy / clipPosition.w;
    screenCoord = ndc * 0.5 + 0.5;
    return screenCoord.x > 0.001 && screenCoord.x < 0.999 &&
           screenCoord.y > 0.001 && screenCoord.y < 0.999;
}

float cinderScreenEdgeFade(vec2 screenCoord) {
    float edgeDistance = min(min(screenCoord.x, 1.0 - screenCoord.x),
                             min(screenCoord.y, 1.0 - screenCoord.y));
    return smoothstep(0.018, 0.085, edgeDistance);
}

vec3 cinderSampleSoftScene(vec2 screenCoord, float blurRadius) {
    vec2 texel = vec2(1.0 / viewWidth, 1.0 / viewHeight);
    vec2 offset = texel * vec2(1.10, 0.72) * blurRadius;
    vec3 center = texture2D(colortex0, screenCoord).rgb;
    vec3 positive = texture2D(colortex0, screenCoord + offset).rgb;
    vec3 negative = texture2D(colortex0, screenCoord - offset).rgb;
    return center * 0.50 + (positive + negative) * 0.25;
}

vec4 cinderTraceWaterReflection(vec3 rayOrigin, vec3 rayDirection, float viewFacing) {
    float maximumTravel = mix(CINDERLIGHT_REFLECTION_DISTANCE,
                              CINDERLIGHT_REFLECTION_DISTANCE * 1.12,
                              1.0 - viewFacing);
    float previousDelta = -100000.0;
    float previousValid = 0.0;

    for (int stepIndex = 0; stepIndex < CINDERLIGHT_REFLECTION_STEPS; ++stepIndex) {
        float stepFraction = float(stepIndex + 1) / float(CINDERLIGHT_REFLECTION_STEPS);
        float travel = mix(0.65, maximumTravel, stepFraction * stepFraction);
        vec3 rayPosition = rayOrigin + rayDirection * travel;

        if (rayPosition.z >= -0.035) break;

        vec2 sampleCoord;
        if (!cinderProjectViewPosition(rayPosition, sampleCoord)) break;

        float sceneDepthRaw = texture2D(depthtex2, sampleCoord).r;
        if (sceneDepthRaw < 0.99975) {
            vec3 scenePosition = cinderReconstructViewPosition(sampleCoord, sceneDepthRaw);
            float rayDepth = -rayPosition.z;
            float sceneDepth = -scenePosition.z;
            float depthDelta = rayDepth - sceneDepth;
            float thickness = 0.42 + sceneDepth * 0.018;
            bool crossedSurface = previousValid > 0.5 && previousDelta < 0.0 && depthDelta >= 0.0;
            bool closeToSurface = abs(depthDelta) < thickness;

            if (crossedSurface || closeToSurface) {
                // Reject recursive water-on-water samples. The metadata buffer is
                // zero for opaque terrain and non-water geometry.
                float reflectedWaterDistance = texture2D(colortex3, sampleCoord).b;
                if (reflectedWaterDistance <= 0.0001) {
                    float edgeFade = cinderScreenEdgeFade(sampleCoord);
                    float proximity = closeToSurface
                                    ? 1.0 - smoothstep(thickness * 0.20, thickness, abs(depthDelta))
                                    : 0.58;
                    float distanceFade = 1.0 - smoothstep(maximumTravel * 0.72,
                                                         maximumTravel, travel);
                    float confidence = edgeFade * proximity * mix(0.72, 1.0, distanceFade);
                    float blurRadius = mix(0.85, 1.45, 1.0 - viewFacing);
                    return vec4(cinderSampleSoftScene(sampleCoord, blurRadius), confidence);
                }
            }

            previousDelta = depthDelta;
            previousValid = 1.0;
        } else {
            previousValid = 0.0;
        }
    }

    // Far reflected rays sample only depth-free sky pixels. This supplements the
    // existing analytic sky reflection with actual rendered clouds, sun and moon.
    vec3 skyPosition = rayOrigin + rayDirection * (maximumTravel * 1.65);
    vec2 skyCoord;
    if (skyPosition.z < -0.035 && cinderProjectViewPosition(skyPosition, skyCoord)) {
        float skyDepth = texture2D(depthtex2, skyCoord).r;
        if (skyDepth > 0.99975) {
            float edgeFade = cinderScreenEdgeFade(skyCoord);
            float skyConfidence = edgeFade * mix(0.46, 0.70, 1.0 - viewFacing);
            return vec4(cinderSampleSoftScene(skyCoord, 1.25), skyConfidence);
        }
    }

    return vec4(0.0);
}

vec3 applyOverworldWaterReflections(vec3 baseWaterColor, vec2 screenCoord, vec4 waterData) {
    // B stores normalized camera distance. Zero means this pixel was not written
    // by the top surface of Overworld water.
    float storedDistance = waterData.b * far;
    if (storedDistance <= 0.0001 || isEyeInWater != 0) return baseWaterColor;

    float frontDepth = texture2D(depthtex0, screenCoord).r;
    if (frontDepth >= 0.999999) return baseWaterColor;

    vec3 viewPosition = cinderReconstructViewPosition(screenCoord, frontDepth);
    float frontDistance = length(viewPosition);
    float distanceTolerance = max(1.35, far / 210.0) + storedDistance * 0.0025;

    // Prevent the stored water mask from affecting a hand, particle, weather
    // sheet, or other geometry rendered later in front of the water.
    if (abs(frontDistance - storedDistance) > distanceTolerance) return baseWaterColor;

    vec2 encodedNormal = (waterData.rg * 2.0 - 1.0) / 12.0;
    float normalY = sqrt(max(1.0 - dot(encodedNormal, encodedNormal), 0.0));
    vec3 worldNormal = safeNormalize(vec3(encodedNormal.x, normalY, encodedNormal.y));
    vec3 viewNormal = safeNormalize(mat3(gbufferModelView) * worldNormal);
    vec3 incidentDirection = safeNormalize(viewPosition);

    if (dot(viewNormal, -incidentDirection) < 0.0) viewNormal = -viewNormal;

    float viewFacing = saturate(dot(viewNormal, -incidentDirection));
    vec3 reflectedDirection = safeNormalize(reflect(incidentDirection, viewNormal));
    vec3 rayOrigin = viewPosition + viewNormal * 0.055 + reflectedDirection * 0.12;
    vec4 tracedReflection = cinderTraceWaterReflection(rayOrigin, reflectedDirection, viewFacing);

    if (tracedReflection.a <= 0.0001) return baseWaterColor;

    float grazingFresnel = pow5(1.0 - viewFacing);
    float reflectionWeight = (0.035 + grazingFresnel * CINDERLIGHT_REFLECTION_STRENGTH)
                           * tracedReflection.a;
    reflectionWeight = min(reflectionWeight, 0.34);

    return mix(baseWaterColor, max(tracedReflection.rgb, vec3(0.0)), reflectionWeight);
}

#endif
