#version 120

// Bloom pass 1 of 2: extract bright pixels (torches, lava, sun/moon,
// bright sky) and blur them HORIZONTALLY only. Pass 2 (composite3.fsh)
// blurs vertically and adds the result back onto the scene. Splitting
// into two 1-D blurs (a "separable" blur) is the standard cheap way to
// get a wide blur radius without an expensive 2-D kernel.

#define BLOOM_THRESHOLD 0.65 // Brightness level bloom kicks in at [0.4 0.5 0.55 0.6 0.65 0.7 0.8]

uniform sampler2D colortex0;
uniform float viewWidth;

varying vec2 texcoord;

/* RENDERTARGETS: 2 */
void main() {
    float texelSize = 1.0 / viewWidth;
    float weights[5];
    weights[0] = 0.227027;
    weights[1] = 0.1945946;
    weights[2] = 0.1216216;
    weights[3] = 0.054054;
    weights[4] = 0.016216;

    vec3 center = texture2D(colortex0, texcoord).rgb;
    float centerLuma = dot(center, vec3(0.299, 0.587, 0.114));
    vec3 sum = center * step(BLOOM_THRESHOLD, centerLuma) * weights[0];

    for (int i = 1; i < 5; i++) {
        vec2 offset = vec2(texelSize * float(i) * 2.0, 0.0);

        vec3 samplePos = texture2D(colortex0, texcoord + offset).rgb;
        float lumaPos = dot(samplePos, vec3(0.299, 0.587, 0.114));
        sum += samplePos * step(BLOOM_THRESHOLD, lumaPos) * weights[i];

        vec3 sampleNeg = texture2D(colortex0, texcoord - offset).rgb;
        float lumaNeg = dot(sampleNeg, vec3(0.299, 0.587, 0.114));
        sum += sampleNeg * step(BLOOM_THRESHOLD, lumaNeg) * weights[i];
    }

    gl_FragData[0] = vec4(sum, 1.0);
}
