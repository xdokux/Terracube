uniform sampler2D colortex0;
uniform sampler2D colortex3;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;

uniform float near;
uniform float far;

in vec2 texcoord;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

void main() {
    color = texture(colortex0, texcoord);
    float mask = texture(colortex3, texcoord).r;
    float glow = 0.0;

    if (abs(mask - 8.0) < 0.1) {
        float z0 = texture(depthtex0, texcoord).r;
        float z1 = texture(depthtex1, texcoord).r;

        float ndc0 = z0 * 2.0 - 1.0;
        float ndc1 = z1 * 2.0 - 1.0;

        float d0 = (2.0 * near * far) / (far + near - ndc0 * (far - near));
        float d1 = (2.0 * near * far) / (far + near - ndc1 * (far - near));

        float diff = abs(d0 - d1);

        glow = smoothstep(0.8, 0.01, diff);
        glow = pow(glow, 5.0) + 0.002;
    }

    color.rgb += glow * vec3(0.7, 0.1, 1.0) * 15.0;
}