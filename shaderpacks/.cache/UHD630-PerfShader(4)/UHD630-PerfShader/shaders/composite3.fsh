#version 120

// Bloom pass 2 of 2: blur colortex2 (the horizontally-blurred bright
// pass from composite2.fsh) VERTICALLY, then add the result back onto
// the actual scene color.

#define BLOOM_STRENGTH 0.4 // Bloom intensity [0.1 0.2 0.3 0.4 0.5 0.6 0.8]

uniform sampler2D colortex0;
uniform sampler2D colortex2;
uniform float viewHeight;

varying vec2 texcoord;

/* RENDERTARGETS: 0 */
void main() {
    float texelSize = 1.0 / viewHeight;
    float weights[5];
    weights[0] = 0.227027;
    weights[1] = 0.1945946;
    weights[2] = 0.1216216;
    weights[3] = 0.054054;
    weights[4] = 0.016216;

    vec3 sum = texture2D(colortex2, texcoord).rgb * weights[0];

    for (int i = 1; i < 5; i++) {
        vec2 offset = vec2(0.0, texelSize * float(i) * 2.0);
        sum += texture2D(colortex2, texcoord + offset).rgb * weights[i];
        sum += texture2D(colortex2, texcoord - offset).rgb * weights[i];
    }

    vec3 base = texture2D(colortex0, texcoord).rgb;
    vec3 result = base + sum * BLOOM_STRENGTH;

    gl_FragData[0] = vec4(clamp(result, 0.0, 1.0), 1.0);
}
