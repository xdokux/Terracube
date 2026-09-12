#version 120

uniform sampler2D colortex0; // scene color
uniform sampler2D colortex1; // normal (rgb) + reflective mask (a)
uniform sampler2D depthtex0;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

varying vec2 texcoord;

vec3 toViewSpace(vec2 uv, float depth) {
    vec4 clip = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 view = gbufferProjectionInverse * clip;
    return view.xyz / view.w;
}

/* RENDERTARGETS: 0 */
void main() {
    vec4 base = texture2D(colortex0, texcoord);
    vec4 matData = texture2D(colortex1, texcoord);
    float isReflective = matData.a;

    // Early-out: skip all SSR math for the ~95% of pixels that aren't water.
    // This early-out is the single most important line for iGPU performance
    // in this pass - without it every pixel on screen pays the ray-march cost.
    if (isReflective < 0.5) {
        gl_FragData[0] = base;
        return;
    }

    float depth = texture2D(depthtex0, texcoord).r;
    vec3 viewPos = toViewSpace(texcoord, depth);
    vec3 n = normalize(matData.rgb * 2.0 - 1.0);
    vec3 viewDir = normalize(viewPos);
    vec3 reflectDir = reflect(viewDir, n);

    // Fixed 8-step screen-space ray march. No refinement/binary-search
    // pass - deliberately traded accuracy for speed.
    vec3 rayPos = viewPos;
    float stepSize = 0.35;
    vec3 hitColor = vec3(0.0);
    float hit = 0.0;

    for (int i = 0; i < 8; i++) {
        rayPos += reflectDir * stepSize;

        vec4 clipPos = gbufferProjection * vec4(rayPos, 1.0);
        clipPos.xyz /= clipPos.w;
        vec2 sampleUV = clipPos.xy * 0.5 + 0.5;

        if (sampleUV.x < 0.0 || sampleUV.x > 1.0 || sampleUV.y < 0.0 || sampleUV.y > 1.0) break;

        float sampleDepth = texture2D(depthtex0, sampleUV).r;
        vec3 sampleViewPos = toViewSpace(sampleUV, sampleDepth);

        if (rayPos.z < sampleViewPos.z + 0.1 && rayPos.z > sampleViewPos.z - 0.5) {
            hitColor = texture2D(colortex0, sampleUV).rgb;
            hit = 1.0;
            break;
        }

        stepSize *= 1.4; // grow step size so 8 steps still cover real distance
    }

    // No hit -> fall back to a darkened tint of the water color itself,
    // rather than an expensive skybox/cubemap sample.
    vec3 reflection = mix(base.rgb * 0.6, hitColor, hit);
    vec3 result = mix(base.rgb, reflection, 0.5);

    gl_FragData[0] = vec4(result, base.a);
}
