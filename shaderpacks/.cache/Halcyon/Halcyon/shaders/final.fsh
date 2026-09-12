#version 120

uniform sampler2D colortex0;
varying vec2 texcoord;

// Static exposure for now - see README re: auto-exposure being a known simplification
const float EXPOSURE = 1.1;

// Krzysztof Narkowicz's widely-used ACES filmic curve approximation
vec3 acesFilm(vec3 x) {
    float a = 2.51;
    float b = 0.03;
    float c = 2.43;
    float d = 0.59;
    float e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

void main() {
    vec3 color = texture2D(colortex0, texcoord).rgb * EXPOSURE;

    color = acesFilm(color);
    color = pow(color, vec3(1.0 / 2.2));

    float vignetteDist = distance(texcoord, vec2(0.5));
    float vignette = smoothstep(0.75, 0.35, vignetteDist);
    color *= mix(0.85, 1.0, vignette);

    gl_FragColor = vec4(color, 1.0);
}
