uniform sampler2D colortex7;
uniform float viewHeight;

in vec2 texcoord;

/* RENDERTARGETS: 8 */
layout(location = 0) out vec3 color;

#define BLOOM_INTENSITY 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]

void main() {
    #if BLOOM_INTENSITY == 0.0
        color = vec4(0.0);
        return;
    #endif
    float step = 1.0 / viewHeight;
    vec3 accumulator = vec3(0.0);
    float totalWeight = 0.0;

    for (float i = -24.0; i <= 24.0; i += 0.5) {
        float weight = exp(-0.5 * (i * i) / (12.0 * 12.0));
        accumulator += texture(colortex7, texcoord + vec2(0.0, i * step)).rgb * weight;
        totalWeight += weight;
    }

    color.rgb = accumulator / totalWeight;
}