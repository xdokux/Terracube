#version 120

varying vec2 uv;
uniform sampler2D colortex0;

float luminance(vec3 color) {
    return dot(color, vec3(0.2125f, 0.7153f, 0.0721f));
}

/*
const int colortex0Format = RGBA32F;
*/

#define SATURATION 1.15      // [1.0 1.05 1.1 1.15 1.2 1.25 1.3 1.35 1.4 1.45 1.5]

const float saturation = SATURATION;

void main() {
    vec3 albedo = texture2D(colortex0, uv).rgb;

    vec3 desaturated = vec3(luminance(albedo));

    albedo = mix(desaturated, albedo, saturation);

    gl_FragColor = vec4(albedo, 1.0f);
}
