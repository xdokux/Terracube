uniform sampler2D colortex10;
uniform float viewWidth;

in vec2 texcoord;

/* RENDERTARGETS: 11 */
layout(location = 0) out vec3 color;

#define BLOOM_INTENSITY 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]

void main() {
    #if BLOOM_INTENSITY == 0.0
        color = vec4(0.0);
        return;
    #endif
    float step = 1.0 / viewWidth;
    vec3 accumulator = vec3(0.0);
    float totalWeight = 0.0;

    for (float i = -216.0; i <= 216.0; i += 4.5) {
        float weight = exp(-0.5 * (i * i) / (108.0 * 108.0));
        accumulator += texture(colortex10, texcoord + vec2(i * step, 0.0)).rgb * weight;
        totalWeight += weight;
    }

    color.rgb = accumulator / totalWeight;
}