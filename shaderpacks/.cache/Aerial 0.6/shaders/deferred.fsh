#version 120
// AETHER deferred — atmosphere, celestial bodies, volumetric clouds
#include "/lib/settings.glsl"
#include "/lib/common.glsl"

uniform sampler2D colortex0;
uniform sampler2D depthtex0;
uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 cameraPosition;
uniform mat4 gbufferModelView;
uniform mat4 gbufferProjectionInverse;
uniform float frameTimeCounter;
uniform float rainStrength;
uniform float thunderStrength;
uniform float wetness;
uniform int worldTime;
uniform float viewWidth, viewHeight;

varying vec2 texcoord;

vec3 viewToWorldDir(vec3 v) { return v * mat3(gbufferModelView); }

// ---------------- Volumetric clouds ----------------
const float CLOUD_BOTTOM = 320.0;
const float CLOUD_TOP    = 520.0;

// Cheap variant for sun-shadow probes: base shape only, no detail octaves
float cloudDensityCheap(vec3 p, float coverage) {
    float h = clamp((p.y - CLOUD_BOTTOM) / (CLOUD_TOP - CLOUD_BOTTOM), 0.0, 1.0);
    float heightShape = smoothstep(0.0, 0.25, h) * smoothstep(1.0, 0.55, h);
    vec3 q = p * 0.0016 + vec3(frameTimeCounter * 0.006, 0.0, frameTimeCounter * 0.002);
    float base = noise3(q * 2.0) * 0.6 + noise3(q * 4.3) * 0.3;
    float d = base + 0.15 - (1.15 - coverage);
    d += thunderStrength * 0.35 * smoothstep(0.3, 0.9, base);
    return max(d, 0.0) * heightShape;
}

float cloudDensity(vec3 p, float coverage) {
    float h = clamp((p.y - CLOUD_BOTTOM) / (CLOUD_TOP - CLOUD_BOTTOM), 0.0, 1.0);
    float heightShape = smoothstep(0.0, 0.25, h) * smoothstep(1.0, 0.55, h);

    vec3 q = p * 0.0016 + vec3(frameTimeCounter * 0.006, 0.0, frameTimeCounter * 0.002);
    float base = fbm(q);
    float detail = fbm(q * 5.3 + vec3(0.0, frameTimeCounter * 0.01, 0.0));

    float d = base + detail * 0.28 - (1.15 - coverage);
    // Storm cells: taller, denser structures
    d += thunderStrength * 0.35 * smoothstep(0.3, 0.9, base);
    return max(d, 0.0) * heightShape;
}

vec4 marchClouds(vec3 worldDir, vec3 sunW, vec3 sunLight, float coverage) {
    if (worldDir.y < 0.02) return vec4(0.0);

    #if CLOUD_QUALITY == 0
    const int STEPS = 12;
    #elif CLOUD_QUALITY == 1
    const int STEPS = 24;
    #else
    const int STEPS = 40;
    #endif

    float t0 = (CLOUD_BOTTOM - cameraPosition.y) / worldDir.y;
    float t1 = (CLOUD_TOP    - cameraPosition.y) / worldDir.y;
    if (t1 < 0.0) return vec4(0.0);
    t0 = max(t0, 0.0);

    float stepLen = (t1 - t0) / float(STEPS);
    float jitter = ign(gl_FragCoord.xy);
    float t = t0 + stepLen * jitter;

    vec3 scatterSum = vec3(0.0);
    float transmit = 1.0;
    float mu = dot(worldDir, sunW);
    float phase = phaseMie(mu, 0.35) + phaseMie(mu, -0.15) * 0.5 + 0.08;

    for (int i = 0; i < STEPS; i++) {
        vec3 p = cameraPosition + worldDir * t;
        float dens = cloudDensity(p, coverage);
        if (dens > 0.0) {
            // Cheap self-shadow: two low-detail samples toward the sun
            float shade = cloudDensityCheap(p + sunW * 45.0, coverage) * 0.7
                        + cloudDensityCheap(p + sunW * 120.0, coverage) * 0.4;
            vec3 light = sunLight * exp(-shade * 3.2) * phase
                       + vec3(0.25, 0.32, 0.45) * 0.12 * (1.0 - thunderStrength * 0.7);
            float ext = dens * stepLen * 0.045;
            scatterSum += light * transmit * (1.0 - exp(-ext)) * 2.6;
            transmit *= exp(-ext);
            if (transmit < 0.02) break;
        }
        t += stepLen;
    }
    // Fade clouds into the horizon haze
    float horizonFade = smoothstep(0.02, 0.14, worldDir.y);
    return vec4(scatterSum, (1.0 - transmit) * horizonFade);
}

void main() {
    float depth = texture2D(depthtex0, texcoord).r;
    vec3 color = texture2D(colortex0, texcoord).rgb;

    if (depth >= 1.0) {
        // Reconstruct world-space view ray
        vec4 ndc = gbufferProjectionInverse * vec4(vec3(texcoord, 1.0) * 2.0 - 1.0, 1.0);
        vec3 worldDir = normalize(viewToWorldDir(ndc.xyz / ndc.w));
        vec3 sunW  = normalize(viewToWorldDir(normalize(sunPosition)));
        vec3 moonW = normalize(viewToWorldDir(normalize(moonPosition)));

        float haze = HAZE_HUMIDITY * 0.6 + wetness * 0.8 + thunderStrength * 0.6;
        vec3 trans;
        vec3 sky = skyScatter(worldDir, sunW, haze, trans) * SUN_INTENSITY * 3.0;

        // Night sky: faint moon-scattered blue + stars
        vec3 nightSky = skyScatter(worldDir, moonW, haze, trans) * 0.02;
        sky += nightSky * vec3(0.55, 0.7, 1.1);
        float night = smoothstep(0.05, -0.12, sunW.y);
        if (night > 0.0 && worldDir.y > 0.0) {
            vec3 sp = floor(worldDir * 220.0);
            float star = step(0.9985, hash13(sp));
            star *= 0.4 + 0.6 * sin(frameTimeCounter * 2.0 + hash13(sp) * 20.0);
            sky += star * night * (1.0 - rainStrength) * 0.6;
        }

        // Sun & moon discs with limb glow
        float sunDot = dot(worldDir, sunW);
        float sunDisc = smoothstep(0.99955, 0.99985, sunDot);
        sky += sunDisc * sunColor(sunW, haze) * 120.0 * SUN_INTENSITY;
        sky += pow(max(sunDot, 0.0), 900.0) * sunColor(sunW, haze) * 4.0;
        float moonDisc = smoothstep(0.9996, 0.9999, dot(worldDir, moonW));
        sky += moonDisc * vec3(0.7, 0.78, 0.95) * 1.6;

        // Storm darkening
        sky *= 1.0 - thunderStrength * 0.55 - rainStrength * 0.25;

        #ifdef CLOUDS_ENABLED
        float coverage = CLOUD_COVERAGE + rainStrength * 0.3 + thunderStrength * 0.25;
        vec3 sunLight = sunColor(sunW, haze) * SUN_INTENSITY * 3.0 * (1.0 - thunderStrength * 0.6);
        if (sunW.y < 0.0) sunLight = vec3(0.02, 0.025, 0.04); // moonlit clouds
        vec4 clouds = marchClouds(worldDir, sunW.y > 0.0 ? sunW : moonW, sunLight, coverage);
        sky = mix(sky, clouds.rgb, clouds.a);
        #endif

        color = sky;
    } else {
        // Solid gbuffer albedo → linear HDR space for the lighting pass
        color = srgbToLinear(color);
    }

/* DRAWBUFFERS:0 */
    gl_FragData[0] = vec4(color, 1.0);
}
