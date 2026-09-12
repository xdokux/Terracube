#version 330 compatibility

#define SSAO_ENABLED
#define SSAO_SAMPLES 100 //[25 50 75 100 125 150]
#define SSAO_RADIUS 0.3 //[0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
#define SSAO_STRENGTH 1.0 //[0.25 0.5 0.75 1.0 1.25 1.5 1.75 2.0]

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex6;
uniform sampler2D depthtex0;
uniform sampler2D noisetex;

in vec2 texcoord;

#include "/world-1/lib_world-1.glsl"

float LinearDepth(float z) {
    return 1.0 / ((1 - far / near) * z + (far / near));
}

float rand(vec2 co)
{
    return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

vec3 sampleHemisphereCosineDistributed(int sampleIndex, vec3 normal)
{
    float u1 = rand(vec2(sampleIndex, 0.0));
    float u2 = rand(vec2(sampleIndex, 1.0));

    float r = sqrt(u1);
    float theta = 2.0 * 3.14159265 * u2;

    float x = r * cos(theta);
    float y = r * sin(theta);
    float z = sqrt(1.0 - u1);

    // Now create TBN matrix to align to normal
    vec3 tangent = normalize(cross(normal, texture(noisetex, texcoord * 8.0).xyz));
    vec3 bitangent = cross(normal, tangent);
    mat3 TBN = mat3(tangent, bitangent, normal);

    return TBN * (vec3(x, y, z) * SSAO_RADIUS); // World/view space sample
}

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outColor0;

void main() {
	vec4 color = texture(colortex0, texcoord);
    float depth = texture(depthtex0, texcoord).r;
    vec3 normal = texture(colortex1, texcoord).xyz * 2.0 - 1.0;

    color.rgb = pow(color.rgb, vec3(2.2));

#ifdef SSAO_ENABLED
    vec3 screenPos = vec3(texcoord, depth);
    vec3 playerPos = ViewPosToPlayerPos(ScreenPosToViewPos(screenPos));

    int occluded = 0;

    for(int i = 0; i < SSAO_SAMPLES; i++) {

        // Create random point on hemisphere
        vec3 sample = sampleHemisphereCosineDistributed(i, normal);

        // Add sample coords to fragment coords in player space then convert back to screen space
        vec3 screenSpaceSample = ViewPosToScreenPos(PlayerPosToViewPos(playerPos + sample));

        float linDepthAtSample = LinearDepth(screenSpaceSample.z);
        float linDepthClosest = LinearDepth(texture(depthtex0, screenSpaceSample.xy).r);

        // Check if occluded
        if(linDepthAtSample > linDepthClosest && (linDepthAtSample - linDepthClosest) < 0.03) {
            occluded += 1;
        }
    }

    float occlusion = float(occluded)/float(SSAO_SAMPLES);
    //occlusion = pow(occlusion * 2.0, 2.0);

    float linDepth = length(ScreenPosToViewPos(vec3(texcoord, depth)))/far;
    vec2 aoFalloff = mix(vec2(0.1, 0.3), vec2(0.0, 0.1), clamp(float(isEyeInWater), 0.0, 1.0));
    aoFalloff *= 1.0 - texture(colortex6, texcoord).r;
    float ao = mix(1.0 - occlusion * SSAO_STRENGTH * 0.5, 1.0, smoothstep(aoFalloff.x, aoFalloff.y, linDepth));
    color.rgb *= ao;
#endif

    color.rgb = pow(color.rgb, vec3(1.0/2.2));

    outColor0 = color;
    //outColor0 = vec4(linDepth);
    //outColor0 = vec4(ao);
    //outColor0 = vec4(rand(texcoord.xx));
}