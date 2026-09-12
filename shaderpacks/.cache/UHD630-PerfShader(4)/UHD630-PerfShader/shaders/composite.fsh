#version 120

// v4 -> v5: this pass previously ray-marched the actual scene for
// reflections (with binary-search refinement, etc.), which is what
// made it "buggy when reflecting other stuff" - screen-space ray
// marching can only reflect what's already visible on screen, so it
// breaks down constantly (missing data off-screen, behind objects,
// etc.). Per your request, this now strictly reflects a procedural
// sky color instead - no scene ray marching at all. This is simpler,
// can't produce the same class of visual bugs, and is considerably
// cheaper, freeing GPU budget for bloom and the other new features.

#define REFLECTION_STRENGTH 0.5 // Overall reflection blend strength [0.2 0.3 0.4 0.5 0.6 0.7 0.8]

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D depthtex0;
uniform mat4 gbufferProjectionInverse;
uniform vec3 shadowLightPosition;
uniform vec3 sunPosition;
uniform vec3 fogColor;

varying vec2 texcoord;

vec3 toViewSpace(vec2 uv, float depth) {
    vec4 clip = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 view = gbufferProjectionInverse * clip;
    return view.xyz / view.w;
}

// Cheap procedural sky gradient + sun/moon glow, evaluated along the
// reflection direction. Deliberately simple (view-space direction vs.
// view-space light vector is sufficient here - no full world-space
// transform needed since we only care about relative angles).
vec3 getSkyColor(vec3 dir, vec3 lightDir, float isSun) {
    vec3 zenithNight  = vec3(0.05, 0.07, 0.15);
    vec3 zenithDay    = vec3(0.25, 0.45, 0.85);
    vec3 horizonNight = vec3(0.12, 0.12, 0.20);
    vec3 horizonDay   = vec3(0.65, 0.75, 0.90);

    vec3 zenith  = mix(zenithNight, zenithDay, isSun);
    vec3 horizon = mix(horizonNight, horizonDay, isSun);

    float t = clamp(dir.y * 0.5 + 0.5, 0.0, 1.0);
    vec3 sky = mix(horizon, zenith, pow(t, 0.6));

    float glow = pow(clamp(dot(dir, lightDir), 0.0, 1.0), 24.0);
    vec3 glowColor = mix(vec3(0.5, 0.6, 0.9), vec3(1.0, 0.85, 0.6), isSun);
    sky += glowColor * glow;

    return sky;
}

/* RENDERTARGETS: 0 */
void main() {
    vec4 base = texture2D(colortex0, texcoord);
    vec4 matData = texture2D(colortex1, texcoord);
    float isReflective = matData.a;

    // Early-out: skip all reflection math for non-reflective pixels.
    if (isReflective < 0.5) {
        gl_FragData[0] = base;
        return;
    }

    float depth = texture2D(depthtex0, texcoord).r;
    vec3 viewPos = toViewSpace(texcoord, depth);
    vec3 n = normalize(matData.rgb * 2.0 - 1.0);
    vec3 viewDir = normalize(viewPos);
    vec3 reflectDir = reflect(viewDir, n);

    float isSun = step(0.5, dot(normalize(shadowLightPosition), normalize(sunPosition)));
    vec3 skyColor = getSkyColor(reflectDir, normalize(shadowLightPosition), isSun);
    // Ground the procedural sky slightly with the actual current
    // biome/weather fog tint so it doesn't look generic in rain, etc.
    skyColor = mix(skyColor, fogColor, 0.25);

    // Fresnel: more reflective at grazing angles, more see-through
    // looking straight down into water.
    float fresnel = pow(1.0 - clamp(dot(-viewDir, n), 0.0, 1.0), 5.0);
    float blendFactor = mix(REFLECTION_STRENGTH * 0.4, REFLECTION_STRENGTH, fresnel);

    vec3 result = mix(base.rgb, skyColor, blendFactor);
    gl_FragData[0] = vec4(result, base.a);
}
