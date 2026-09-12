#version 120

#define GODRAY_STRENGTH 1.0 // Godray strength [0.0 0.25 0.5 0.75 1.0 1.25 1.5 1.75 2.0]
#define NUM_SAMPLES 10      // reduced from 16 (v1) to help offset the shadow-map cost increase

uniform sampler2D colortex0;
uniform sampler2D depthtex0;
uniform mat4 gbufferProjection;
uniform vec3 sunPosition;
uniform float viewWidth;
uniform float frameTimeCounter;

varying vec2 texcoord;

/* RENDERTARGETS: 0 */
void main() {
    vec4 base = texture2D(colortex0, texcoord);

    // sunPosition is a view-space direction; treating it as a distant
    // point and projecting it gives a usable screen-space "sun position"
    // for the ray direction. Standard trick used in most shaderpacks.
    vec4 sunClip = gbufferProjection * vec4(sunPosition, 1.0);

    if (sunClip.w <= 0.05) {
        // Sun is behind (or nearly edge-on to) the camera. v1 only checked
        // <= 0.0, but a small positive w still sends sunScreen to huge
        // coordinates, which was part of what caused whiteout when
        // looking straight up. Early-out with a safety margin instead.
        gl_FragData[0] = base;
        return;
    }

    vec2 sunScreen = (sunClip.xy / sunClip.w) * 0.5 + 0.5;

    vec2 deltaTexCoord = (texcoord - sunScreen);
    deltaTexCoord *= (1.0 / float(NUM_SAMPLES)) * 0.9;

    // Cheap per-pixel dither (no blue-noise texture, no history buffer)
    // to break up banding between the fixed sample steps.
    float dither = fract(sin(dot(texcoord * viewWidth, vec2(12.9898, 78.233))) * 43758.5453 + frameTimeCounter);

    vec2 sampleCoord = texcoord - deltaTexCoord * dither;
    float illuminationDecay = 1.0;
    float godrayAccum = 0.0;
    const float decayFactor = 0.95;
    const float weight = 0.55;

    for (int i = 0; i < NUM_SAMPLES; i++) {
        sampleCoord -= deltaTexCoord;
        float sampleDepth = texture2D(depthtex0, sampleCoord).r;
        float skyMask = step(0.9999, sampleDepth); // 1.0 = sky (unoccluded)
        godrayAccum += skyMask * illuminationDecay * weight;
        illuminationDecay *= decayFactor;
    }

    // BUGFIX (v1 -> v2): v1 divided by an arbitrary "*8.0 / NUM_SAMPLES"
    // fudge factor instead of the actual maximum the accumulation loop
    // can produce. The real max is the geometric series
    // weight * (1 - decay^N) / (1 - decay); dividing by that properly
    // bounds godrayAccum to [0,1] before it's scaled by strength.
    // Without this, bright sky pixels could get pushed 2-3x past white,
    // which is what caused the "everything turns white" effect when
    // looking up - not bloom, just unbounded additive math.
    float maxPossible = weight * (1.0 - pow(decayFactor, float(NUM_SAMPLES))) / (1.0 - decayFactor);
    godrayAccum /= maxPossible; // now safely in [0, 1]

    // Attenuate the effect on pixels that are themselves sky. v2 only
    // reduced this to 25% (mix(1.0, 0.25, ...)), which was still enough
    // to visibly wash out when looking straight up, since in that view
    // almost every pixel on screen IS sky. Fixed by fully zeroing it:
    // real crepuscular rays are visible where light scatters onto
    // foreground surfaces/fog, not by brightening the open sky itself.
    float selfDepth = texture2D(depthtex0, texcoord).r;
    float selfIsSky = step(0.9999, selfDepth);
    float skyAttenuation = mix(1.0, 0.0, selfIsSky);

    godrayAccum *= GODRAY_STRENGTH * 0.5 * skyAttenuation; // capped additive contribution
    // Warmer, more orange tint (was a pale near-white) to match the
    // warmer atmosphere you asked for.
    vec3 godrayColor = vec3(1.0, 0.72, 0.42) * godrayAccum;

    gl_FragData[0] = vec4(clamp(base.rgb + godrayColor, 0.0, 1.0), base.a);
}
