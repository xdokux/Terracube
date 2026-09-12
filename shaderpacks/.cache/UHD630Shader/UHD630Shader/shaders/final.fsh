#version 120

varying vec2 texcoord;

uniform sampler2D colortex0;

vec3 reinhard(vec3 color) {
    return color / (color + vec3(1.0));
}

void main() {
    vec3 color = texture2D(colortex0, texcoord).rgb;
    color = reinhard(color);
    color = pow(color, vec3(1.0 / 2.2)); // gamma correction
    gl_FragColor = vec4(color, 1.0);
}
