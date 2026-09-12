#version 120

uniform sampler2D colortex0;

varying vec2 texcoord;

void main() {
    vec3 color = texture2D(colortex0, texcoord).rgb;
    color = color / (color + vec3(1.0));
    color = pow(color, vec3(1.0 / 2.2));
    gl_FragData[0] = vec4(color, 1.0);
}