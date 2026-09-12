#include "/library/bluenoise.glsl"

#define BLOOM_INTENSITY 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
#define EXPOSURE 1.0 // [0.01 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]

uniform sampler2D colortex0;

uniform sampler2D colortex4;
uniform sampler2D colortex6;

uniform sampler2D colortex8;
uniform sampler2D colortex10;
uniform sampler2D colortex12;

uniform float viewWidth;
uniform float viewHeight;

in vec2 texcoord;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

vec3 tonemap(vec3 x) {
    const float a = 1.3;
    const float b = 0.2;
    const float c = 1.0;
    const float d = 0.8;
    const float e = 0.2;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

void main() {
    color = texture(colortex0, texcoord);

    vec4 reflection = texture(colortex4, texcoord);
    color.rgb = mix(color.rgb, reflection.rgb, reflection.a);

    color += texture(colortex6, texcoord);
    

    float lum = dot(color.rgb, vec3(0.2126, 0.7152, 0.0722));

    float purkinje = 1.0 - smoothstep(0.0, 0.2, lum);
    vec3 rodResponse = vec3(dot(color.rgb, vec3(0.2, 0.7, 0.1)));
    color.rgb = mix(color.rgb, rodResponse * vec3(0.6, 0.8, 1.2), purkinje);

    color.rgb += texture(colortex8, texcoord).rgb * 0.1 * BLOOM_INTENSITY;
    color.rgb += texture(colortex10, texcoord).rgb * 0.1 * BLOOM_INTENSITY;
    color.rgb += texture(colortex12, texcoord).rgb * 0.1 * BLOOM_INTENSITY;
    color.rgb *= EXPOSURE;

    color.rgb = tonemap(color.rgb);

    ivec2 screenCoord = ivec2(gl_FragCoord.xy);
    float noise = getNoise(uvec2(screenCoord));

    color.rgb += (noise - 0.5) / 255.0;
}