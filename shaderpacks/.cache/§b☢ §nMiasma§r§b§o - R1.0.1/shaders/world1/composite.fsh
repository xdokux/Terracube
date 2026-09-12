#version 130

#include "distort.glsl"
#include "/settings.glsl"

in vec2 texcoord;

uniform sampler2D colortex0;
uniform sampler2D depthtex0;

uniform float far, near;
uniform float viewWidth, viewHeight;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;

vec2 viewR = vec2(viewWidth, viewHeight);
float GetLinearDepth(float depth) {
    return (2.0 * near) / (far + near - depth * (far - near));
}
vec2 darkOutlineOffsets[12] = vec2[12](
    vec2( 1.0, 0.0),
    vec2(-1.0, 1.0),
    vec2( 0.0, 1.0),
    vec2( 1.0, 1.0),
    vec2(-2.0, 2.0),
    vec2(-1.0, 2.0),
    vec2( 0.0, 2.0),
    vec2( 1.0, 2.0),
    vec2( 2.0, 2.0),
    vec2(-2.0, 1.0),
    vec2( 2.0, 1.0),
    vec2( 2.0, 0.0)
);
vec3 ViewToPlayer(vec3 pos) {
    return mat3(gbufferModelViewInverse) * pos + gbufferModelViewInverse[3].xyz;
}
void Outline(inout vec3 color, sampler2D depthtex0, vec2 texcoord) {
    vec2 scale = vec2(0.8 / viewR);

    float z0 = texture2D(depthtex0, texcoord).r;
    float linearZ0 = GetLinearDepth(z0);
    float outline = 1.0;
    float z = linearZ0 * far * 2.0;
    float minZ = 1.0, sampleZA = 0.0, sampleZB = 0.0;
    int sampleCount = 12;

    for (int i = 0; i < sampleCount; i++) {
        vec2 offset = scale * darkOutlineOffsets[i];
        sampleZA = texture2D(depthtex0, texcoord + offset).r;
        sampleZB = texture2D(depthtex0, texcoord - offset).r;
        float sampleZsum = GetLinearDepth(sampleZA) + GetLinearDepth(sampleZB);
        outline *= clamp(1.0 - (z - sampleZsum * far), 0.0, 1.0);
        minZ = min(minZ, min(sampleZA, sampleZB));
    }

    if (outline < 0.909091) {
        vec4 viewPos = gbufferProjectionInverse * (vec4(texcoord, minZ, 1.0) * 2.0 - 1.0);
        viewPos /= viewPos.w;
        float lViewPos = length(viewPos.xyz);
        vec3 playerPos = ViewToPlayer(viewPos.xyz);
        vec3 nViewPos = normalize(viewPos.xyz);

        vec3 newColor = vec3(0.03, 0.025, 0.05);

        vec3 color_with_outlines = mix(color, newColor, 1.0 - outline * 1.1);

        float depth = GetLinearDepth(texture2D(depthtex0, texcoord).r);
        color = mix(color_with_outlines, color, clamp(depth, 0.0, 1.0));
    }
}

void main()
{
    vec3 color = texture(colortex0, texcoord).rgb;
	
	Outline(color, depthtex0, texcoord);
	
	/*DRAWBUFFERS:0*/
	gl_FragData[0].rgb = vec3(color);
}
