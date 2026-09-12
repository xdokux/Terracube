#version 120
uniform sampler2D colortex0;
uniform float rainStrength;
varying vec2 texcoord;
vec3 applyVibrance(vec3 color, float amount) {
    float maxCol = max(color.r, max(color.g, color.b));
    float minCol = min(color.r, min(color.g, color.b));
    float saturation = maxCol - minCol;
    vec3 lumCoeff = vec3(0.2126, 0.7152, 0.0722);
    float luma = dot(color, lumCoeff);
    float mask = 1.0 - saturation;
    return mix(color, mix(vec3(luma), color, 1.0 + amount * mask), amount);
}
void main() {
    vec3 color = texture2D(colortex0, texcoord).rgb;
    color = applyVibrance(color, 0.35);
    vec3 tonemapped = color / (color + vec3(0.4));
    color = mix(color, tonemapped, 0.5);
    float contrast = 1.15;
    color = (color - 0.5) * contrast + 0.5;
    if (rainStrength > 0.0) {
        color = mix(color, color * 0.8 + vec3(0.03, 0.05, 0.08) * rainStrength, 0.25);
    }
    vec2 uv = texcoord - 0.5;
    float vDist = length(uv);
    float vignette = smoothstep(0.75, 0.25, vDist);
    color = mix(color * 0.45, color, vignette);
    gl_FragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
