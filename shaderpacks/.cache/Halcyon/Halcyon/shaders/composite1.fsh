#version 120

uniform sampler2D colortex0;
uniform float viewWidth;
uniform float viewHeight;

varying vec2 texcoord;

const float BLOOM_THRESHOLD = 1.0;
const float BLOOM_INTENSITY = 0.25;
const int BLOOM_RADIUS = 2; // 5x5 tap kernel

void main() {
    vec3 base = texture2D(colortex0, texcoord).rgb;
    vec2 texelSize = 1.0 / vec2(viewWidth, viewHeight) * 3.0; // spread the taps out a bit

    vec3 bloom = vec3(0.0);
    float samples = 0.0;

    for (int x = -BLOOM_RADIUS; x <= BLOOM_RADIUS; x++) {
        for (int y = -BLOOM_RADIUS; y <= BLOOM_RADIUS; y++) {
            vec3 s = texture2D(colortex0, texcoord + vec2(x, y) * texelSize).rgb;
            float luma = dot(s, vec3(0.2126, 0.7152, 0.0722));
            float weight = max(luma - BLOOM_THRESHOLD, 0.0);
            bloom += s * weight;
            samples += 1.0;
        }
    }
    bloom /= samples;

    gl_FragColor = vec4(base + bloom * BLOOM_INTENSITY, 1.0);
}
