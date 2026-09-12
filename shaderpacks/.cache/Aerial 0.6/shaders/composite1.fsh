#version 120
// AETHER composite1 — volumetric light, aerial perspective, fog
#include "/lib/settings.glsl"
#include "/lib/common.glsl"

uniform sampler2D colortex0;
uniform sampler2D depthtex0;
uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
uniform sampler2D shadowcolor0;
uniform vec3 sunPosition;
uniform vec3 shadowLightPosition;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjectionInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform float rainStrength;
uniform float thunderStrength;
uniform float wetness;
uniform float frameTimeCounter;
uniform float far;
uniform int isEyeInWater;
uniform ivec2 eyeBrightnessSmooth;

varying vec2 texcoord;

vec2 distortShadow(vec2 p) {
    float len = length(p);
    return p / (len * 0.85 + 0.15);
}

// RGB shadow: white = open, black = blocked, colored = through stained glass
vec3 shadowAt(vec3 viewPos) {
    vec4 sp = shadowProjection * (shadowModelView * (gbufferModelViewInverse * vec4(viewPos, 1.0)));
    sp.xyz /= sp.w;
    if (length(sp.xy) > 0.95) return vec3(1.0);
    sp.xy = distortShadow(sp.xy);
    sp.z *= 0.5;
    sp.xyz = sp.xyz * 0.5 + 0.5;
    float solid = step(sp.z - 0.0012, texture2D(shadowtex1, sp.xy).r);
    float all   = step(sp.z - 0.0012, texture2D(shadowtex0, sp.xy).r);
    vec4 tcol = texture2D(shadowcolor0, sp.xy);
    vec3 tint = mix(tcol.rgb * 1.6, vec3(1.0), all);
    return solid * min(tint, vec3(1.0));
}

void main() {
    float depth = texture2D(depthtex0, texcoord).r;
    vec3 color = texture2D(colortex0, texcoord).rgb;

    vec4 ndc = gbufferProjectionInverse * vec4(vec3(texcoord, depth) * 2.0 - 1.0, 1.0);
    vec3 viewPos = ndc.xyz / ndc.w;
    float dist = length(viewPos);
    if (depth >= 1.0) dist = far * 2.0;

    mat3 mvInv = mat3(gbufferModelView);
    vec3 worldDir = normalize(viewPos * mvInv);
    vec3 sunW = normalize(normalize(sunPosition) * mvInv);
    vec3 lightDirV = normalize(shadowLightPosition);
    float haze = HAZE_HUMIDITY * 0.5 + wetness * 0.7 + thunderStrength * 0.5;
    bool day = sunW.y > -0.05;
    vec3 sunLight = day ? sunColor(sunW, haze) * SUN_INTENSITY : vec3(0.03, 0.04, 0.07);

    // How much sky the camera actually sees — kills fog/god rays in caves
    float eyeSky = float(eyeBrightnessSmooth.y) / 240.0;
    eyeSky = eyeSky * eyeSky;

    // ---------- volumetric light shafts (shadow-marched) ----------
    float mu = dot(normalize(viewPos), lightDirV);
    // Stronger forward scattering + ambient term → clearly visible shafts
    float phase = phaseMie(mu, 0.7) * 1.4 + 0.06;
    const int VSTEPS = 12;
    float marchEnd = min(dist, 80.0);
    vec3 volLight = vec3(0.0);
    // Skip the shadow march entirely when there is no light to scatter
    // (night without moonlight contribution, or facing away with weak phase)
    float shaftPotential = luminance(sunLight) * phase;
    if (shaftPotential > 0.002 || isEyeInWater == 1) {
        float jitter = ign(gl_FragCoord.xy);
        float stepLen = marchEnd / float(VSTEPS);
        for (int i = 0; i < VSTEPS; i++) {
            float t = (float(i) + jitter) * stepLen;
            vec3 p = normalize(viewPos) * t;
            volLight += shadowAt(p); // colored through stained glass
        }
        volLight /= float(VSTEPS);
    }
    float volDensity = 0.016 + haze * 0.022 + rainStrength * 0.022 * FOG_STORM_BOOST;
    if (isEyeInWater == 1) { volDensity = 0.10; sunLight *= vec3(0.2, 0.6, 0.8); }
    vec3 shafts = volLight * sunLight * phase * (1.0 - exp(-marchEnd * volDensity)) * 3.6;
    if (isEyeInWater == 0) shafts *= mix(0.25, 1.0, eyeSky); // indoor rays stay visible but tamed

    // ---------- aerial perspective ----------
    if (isEyeInWater == 0) {
        float fogAmt = 1.0 - exp(-dist * (0.0012 * SKY_DENSITY + haze * 0.0035 + rainStrength * 0.006 * FOG_STORM_BOOST));
        fogAmt *= eyeSky; // no atmospheric fog underground
        if (depth >= 1.0) fogAmt *= smoothstep(0.25, -0.05, worldDir.y); // only thicken toward horizon on sky
        vec3 tr;
        vec3 fogColor = skyScatter(normalize(worldDir + vec3(0.0, 0.04, 0.0)), day ? sunW : -sunW, haze, tr)
                      * (day ? 2.2 : 0.03) * SUN_INTENSITY;
        fogColor *= 1.0 - thunderStrength * 0.5;
        color = mix(color, fogColor, clamp(fogAmt, 0.0, 1.0));
    } else {
        // underwater absorption with depth
        vec3 absorb = vec3(0.45, 0.12, 0.08) * WATER_ABSORPTION;
        color *= exp(-absorb * dist);
        color = mix(color, vec3(0.01, 0.08, 0.12) * (day ? 1.0 : 0.05), 1.0 - exp(-dist * 0.04));
    }

    color += shafts;

/* DRAWBUFFERS:0 */
    gl_FragData[0] = vec4(color, 1.0);
}
