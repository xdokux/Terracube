#version 120

#define GODRAY_STRENGTH 1.0 // Godray strength [0.0 0.25 0.5 0.75 1.0 1.25 1.5 1.75 2.0]
#define NUM_SAMPLES 16      // kept low deliberately for iGPU performance

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

    if (sunClip.w <= 0.0) {
        // Sun is behind the camera - cheap early-out, no godrays to compute.
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

    godrayAccum *= (GODRAY_STRENGTH * 8.0) / float(NUM_SAMPLES);
    vec3 godrayColor = vec3(1.0, 0.96, 0.85) * godrayAccum;

    gl_FragData[0] = vec4(base.rgb + godrayColor, base.a);
}
