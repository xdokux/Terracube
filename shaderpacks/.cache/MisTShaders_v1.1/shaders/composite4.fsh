#version 120

varying vec2 uv;
uniform sampler2D colortex0;
uniform sampler2D colortex4;
uniform sampler2D depthtex0;

/*
const int colortex0Format = RGBA32F;
const int colortex4Format = RGBA32F;
*/

const float contrast = 0.005f;

void main() {
    vec3 albedo = texture2D(colortex0, uv).rgb;
    vec3 blurred = texture2D(colortex4, uv).rgb;
    float depth = texture2D(depthtex0, uv).r;

    if (depth < 0.99999f)
        albedo = albedo + (albedo - blurred) * contrast;

    gl_FragColor = vec4(albedo, 1.0f);
}
