#version 330 compatibility

#include "/library/pad.glsl"

uniform sampler2D colortex0;
uniform sampler2D colortex3;

uniform sampler2D depthtex0;
uniform sampler2D depthtex1;

uniform mat4 gbufferProjectionInverse;
uniform int isEyeInWater;
uniform float near;
uniform float far;

in vec2 texcoord;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

vec3 getWorldPos(float d){
    vec4 ndc = vec4(texcoord * 2.0 - 1.0, d * 2.0 - 1.0, 1.0);
    vec4 v = gbufferProjectionInverse * ndc;
    return v.xyz / v.w;
}

void main() {
    color = texture(colortex0, texcoord);

    float mask = texture(colortex3, texcoord).r;

    vec3 p0 = getWorldPos(texture(depthtex0, texcoord).r);
	vec3 p1 = getWorldPos(texture(depthtex1, texcoord).r);

	if (isEyeInWater == 1) p1 = getWorldPos(0.0);

    float difference = length(p0 - p1);
	if (abs(difference - 0.0) < 0.01) return;
	if (abs(mask - 5.0) > 0.01 && isEyeInWater != 1) return;

    vec3 waterColor = vec3(0.0, 0.17, 0.3) * 2.0;
    float intensity = 0.02;

    float factor = clamp(difference * intensity, 0.0, 1.0);
    factor = pow(factor, 0.2);

    color.rgb *= mix(vec3(1.0), waterColor, factor);

    if (isEyeInWater != 1) {
        float foam = 1.0 - smoothstep(0.0, 1.0, difference);
        color.rgb += foam * 0.1;
    }
}