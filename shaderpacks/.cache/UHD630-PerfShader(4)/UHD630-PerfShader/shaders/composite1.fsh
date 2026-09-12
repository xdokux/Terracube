#version 120

// v3 -> v4: this pass was rewritten from scratch. It previously did a
// screen-space radial blur toward the sun's projected screen position,
// which only ever produced visible rays when the sun was on-screen,
// and was prone to banding/grain from the low sample count. This
// version instead raymarches each pixel's own view ray through the
// actual shadow map (same technique Photon/Complementary Reimagined
// use, simplified for performance) - it works in every view direction
// and the shadow-map-based occlusion test is inherently smoother.

#define GODRAY_STRENGTH 1.0     // Godray brightness [0.0 0.2 0.4 0.6 0.8 1.0 1.2 1.4 1.6 1.8 2.0]
#define GODRAY_MAX_DIST 40.0    // Max raymarch distance in blocks - higher = rays reach further but costs more [24.0 32.0 40.0 48.0 64.0]
#define GODRAY_SAMPLES 10       // Raymarch steps - more = smoother but slower (loop bound, not a live slider) [6 8 10 12 14 16]
#define SHADOW_MAP_BIAS 0.9     // Shadow distortion strength - MUST match shadow.vsh [0.0 0.5 0.7 0.8 0.85 0.9 0.95]

uniform sampler2D colortex0;
uniform sampler2D depthtex0;
uniform sampler2D shadowtex1; // opaque-only depth - godrays only check hard occlusion, not colored glass
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform vec3 shadowLightPosition;
uniform vec3 sunPosition; // compared against shadowLightPosition to tell day (sun) from night (moon)

varying vec2 texcoord;

float getDistortFactor(vec2 pos) {
    return (1.0 - SHADOW_MAP_BIAS) + length(pos) * SHADOW_MAP_BIAS;
}

vec3 distortShadowClipPos(vec3 clipPos) {
    float distortFactor = getDistortFactor(clipPos.xy);
    return vec3(clipPos.xy / distortFactor, clipPos.z);
}

vec3 toViewSpace(vec2 uv, float depth) {
    vec4 clip = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 view = gbufferProjectionInverse * clip;
    return view.xyz / view.w;
}

/* RENDERTARGETS: 0 */
void main() {
    vec4 base = texture2D(colortex0, texcoord);

    float sceneDepth = texture2D(depthtex0, texcoord).r;
    vec3 sceneViewPos = toViewSpace(texcoord, sceneDepth);
    float sceneDist = length(sceneViewPos);

    // Don't march further than what's actually visible (stops rays from
    // appearing to shine "through" solid geometry in front of the
    // camera), and cap total distance for performance.
    float marchDist = min(sceneDist, GODRAY_MAX_DIST);
    vec3 viewDir = sceneViewPos / max(sceneDist, 0.0001);

    // Precompute the combined view->shadow-clip matrix once per pixel
    // instead of once per raymarch step.
    mat4 toShadowClip = shadowProjection * shadowModelView * gbufferModelViewInverse;

    // Interleaved gradient noise dither - cheap, and distributes error
    // as fine grain rather than macro banding (this is the actual fix
    // for the "extremely grainy" complaint, not just more samples).
    vec3 magic = vec3(0.06711056, 0.00583715, 52.9829189);
    float dither = fract(magic.z * fract(dot(gl_FragCoord.xy, magic.xy)));

    float stepSize = marchDist / float(GODRAY_SAMPLES);
    float accum = 0.0;

    for (int i = 0; i < GODRAY_SAMPLES; i++) {
        float t = (float(i) + dither) * stepSize;
        vec3 samplePos = viewDir * t;

        vec4 shadowClip = toShadowClip * vec4(samplePos, 1.0);
        shadowClip.xyz = distortShadowClipPos(shadowClip.xyz);
        vec3 shadowScreen = shadowClip.xyz * 0.5 + 0.5;

        float lit = 1.0;
        if (shadowScreen.x >= 0.0 && shadowScreen.x <= 1.0 &&
            shadowScreen.y >= 0.0 && shadowScreen.y <= 1.0 &&
            shadowScreen.z >= 0.0 && shadowScreen.z <= 1.0) {
            float shadowDepth = texture2D(shadowtex1, shadowScreen.xy).r;
            lit = (shadowScreen.z - 0.001 > shadowDepth) ? 0.0 : 1.0;
        }

        // Mild exponential falloff so nearer light contributes a bit
        // more than far light (cheap stand-in for real fog scattering).
        float falloff = exp(-t * 0.02);
        accum += lit * falloff;
    }

    accum /= float(GODRAY_SAMPLES); // normalized to [0,1]

    // Forward-scattering approximation: rays are strongest looking
    // toward the sun, but still present (just dimmer, not absent) in
    // other directions - this replaces the old hard "only works facing
    // the sun" limitation with a smooth falloff instead.
    float sunDot = dot(viewDir, normalize(shadowLightPosition));
    float scatter = mix(0.3, 1.0, clamp(sunDot * 0.5 + 0.5, 0.0, 1.0));

    // Tightly capped additive contribution - this is what fixes "too
    // bright on pretty much all settings." Max possible addition here
    // is GODRAY_STRENGTH * 0.35 (e.g. ~0.7 even at the slider's max of
    // 2.0), not the unbounded/mis-normalized math from before.
    accum *= GODRAY_STRENGTH * 0.35 * scatter;

    // BUGFIX: shadowLightPosition automatically points at whichever
    // celestial body is currently casting shadows (sun by day, moon by
    // night) - but the godray TINT color was hardcoded warm/orange
    // regardless, so night godrays incorrectly kept the daytime color.
    // Fix: check whether shadowLightPosition currently matches
    // sunPosition (day) or not (night, i.e. it's actually moonPosition)
    // and pick the tint accordingly.
    float isSun = step(0.5, dot(normalize(shadowLightPosition), normalize(sunPosition)));
    accum *= mix(0.4, 1.0, isSun); // moonlight godrays dimmer overall, not just cooler-toned

    vec3 warmSunTint = vec3(1.0, 0.72, 0.42);
    vec3 coolMoonTint = vec3(0.55, 0.65, 0.85);
    vec3 godrayTint = mix(coolMoonTint, warmSunTint, isSun);

    vec3 godrayColor = godrayTint * accum;
    gl_FragData[0] = vec4(clamp(base.rgb + godrayColor, 0.0, 1.0), base.a);
}
