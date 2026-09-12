// AETHER — opaque lighting body (runs BEFORE translucents so
// water/glass blend over a lit scene): shadows, GI, AO, blocklight
// Wrappers define DIM_NETHER / DIM_END before including this.
#include "/lib/settings.glsl"
#include "/lib/common.glsl"

uniform vec3 fogColor;

uniform sampler2D colortex0;   // linear albedo / sky HDR
uniform sampler2D colortex1;   // normal + material
uniform sampler2D colortex5;   // lightmap
uniform sampler2D depthtex0;
uniform sampler2D shadowtex0;   // depth incl. translucents
uniform sampler2D shadowtex1;   // depth, opaque only
uniform sampler2D shadowcolor0; // translucent color (for tinted shadows)

uniform vec3 sunPosition;
uniform vec3 shadowLightPosition;
uniform mat4 gbufferModelView;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform mat4 gbufferModelViewInverse;
uniform float rainStrength;
uniform float thunderStrength;
uniform float wetness;
uniform float frameTimeCounter;
uniform float viewWidth, viewHeight;
uniform int worldTime;

varying vec2 texcoord;

vec3 getViewPos(vec2 uv, float depth) {
    vec4 ndc = gbufferProjectionInverse * vec4(vec3(uv, depth) * 2.0 - 1.0, 1.0);
    return ndc.xyz / ndc.w;
}

vec2 distortShadow(vec2 p) {
    float len = length(p);
    return p / (len * 0.85 + 0.15);
}

// ---------------- Soft shadows (rotated-disk PCF, normal-offset) ----------------
// Returns RGB: white = lit, black = shadow, colored = light through stained glass/water
vec3 sampleShadow(vec3 viewPos, vec3 normal, float NoL) {
    // Normal-offset kills wall/ceiling light leaks far better than depth bias
    vec3 worldNormal = mat3(gbufferModelViewInverse) * normal;
    vec4 worldPos = gbufferModelViewInverse * vec4(viewPos, 1.0);
    worldPos.xyz += worldNormal * (0.03 + length(viewPos) * 0.006) * (1.0 - NoL * 0.5);

    vec4 shadowPos = shadowProjection * (shadowModelView * worldPos);
    shadowPos.xyz /= shadowPos.w;
    float distFade = smoothstep(0.85, 1.0, length(shadowPos.xy));
    shadowPos.xy = distortShadow(shadowPos.xy);
    shadowPos.z *= 0.5;
    shadowPos.xyz = shadowPos.xyz * 0.5 + 0.5;
    if (distFade >= 1.0) return vec3(1.0);

    float bias = 0.0006 + 0.0010 * (1.0 - NoL);

    #if SHADOW_QUALITY == 1
    const int TAPS = 4;
    #elif SHADOW_QUALITY == 2
    const int TAPS = 8;
    #else
    const int TAPS = 16;
    #endif

    float rot = ign(gl_FragCoord.xy) * 2.0 * PI;
    mat2 rotM = mat2(cos(rot), -sin(rot), sin(rot), cos(rot));
    float radius = 1.3 / float(shadowMapResolution);

    // Early out: two probe taps — if both agree and no translucent is
    // involved, skip the full PCF disk (most pixels take this path)
    float p0 = step(shadowPos.z - bias, texture2D(shadowtex1, shadowPos.xy).r);
    float p1 = step(shadowPos.z - bias, texture2D(shadowtex1, shadowPos.xy + vec2(radius, radius * 0.7)).r);
    float pAll = step(shadowPos.z - bias, texture2D(shadowtex0, shadowPos.xy).r);
    if (p0 == p1 && p0 == pAll) return mix(vec3(p0), vec3(1.0), distFade);

    vec3 sum = vec3(0.0);
    for (int i = 0; i < TAPS; i++) {
        float a = (float(i) + 0.5) / float(TAPS) * 2.0 * PI * 2.4;
        float r = sqrt((float(i) + 0.5) / float(TAPS));
        vec2 offs = rotM * vec2(cos(a), sin(a)) * r * radius;
        vec2 suv = shadowPos.xy + offs;
        float solid = step(shadowPos.z - bias, texture2D(shadowtex1, suv).r);
        float all   = step(shadowPos.z - bias, texture2D(shadowtex0, suv).r);
        // Blocked only by a translucent → tint sunlight with its color
        vec4 tcol = texture2D(shadowcolor0, suv);
        vec3 tint = mix(tcol.rgb * (1.0 - tcol.a * 0.4) * 1.6, vec3(1.0), all);
        sum += solid * min(tint, vec3(1.0));
    }
    return mix(sum / float(TAPS), vec3(1.0), distFade);
}

// -------- SSAO + SSGI + voxel-style emissive light bleed --------
void ssgi(vec3 viewPos, vec3 normal, out float ao, out vec3 bounce, out vec3 emisLight) {
    ao = 1.0; bounce = vec3(0.0); emisLight = vec3(0.0);
    // Distant pixels: AO/GI is sub-pixel there — skip entirely
    if (-viewPos.z > GI_DISTANCE) return;
    ao = 0.0;
    const int SAMPLES = GI_SAMPLES;
    float radius = clamp(1.2 / max(-viewPos.z * 0.08, 0.4), 0.25, 2.0);
    float rot = ign(gl_FragCoord.xy) * 2.0 * PI + frameTimeCounter;

    for (int i = 0; i < SAMPLES; i++) {
        float a = rot + float(i) * 2.399963;
        float r = sqrt((float(i) + 0.5) / float(SAMPLES)) * radius;
        vec3 dir = vec3(cos(a), sin(a), 0.0);
        vec3 samplePos = viewPos + (dir - normal * dot(dir, normal) + normal * 0.6) * r;

        vec4 clip = gbufferProjection * vec4(samplePos, 1.0);
        vec2 uv = clip.xy / clip.w * 0.5 + 0.5;
        if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) continue;

        float sd = texture2D(depthtex0, uv).r;
        vec3 sv = getViewPos(uv, sd);
        vec3 diff = sv - viewPos;
        float dist = length(diff);
        float occ = max(dot(normal, diff / max(dist, 1e-4)) - 0.08, 0.0)
                  * smoothstep(radius * 1.5, radius * 0.2, dist);
        ao += occ;

        vec3 sAlbedo = texture2D(colortex0, uv).rgb;
        float sMat = texture2D(colortex1, uv).a;
        float near = smoothstep(radius * 2.0, 0.0, dist);
        if (sMat > 0.85) {
            // Emissive found nearby: check for an occluder along the path so
            // light doesn't spill through blocks (screen-space shadow).
            // A single mid-point test misses corner geometry — if the wall
            // sits closer to either endpoint than the middle (the common
            // case at a room corner, like the ceiling seam in this scene),
            // the ray "sees past" it and the light leaks through. Sample at
            // both 1/3 and 2/3 along the path so a wall near either end is
            // still caught.
            vec2 uv1 = mix(texcoord, uv, 0.33);
            vec2 uv2 = mix(texcoord, uv, 0.66);
            vec3 v1 = getViewPos(uv1, texture2D(depthtex0, uv1).r);
            vec3 v2 = getViewPos(uv2, texture2D(depthtex0, uv2).r);
            vec3 expect1 = mix(viewPos, sv, 0.33);
            vec3 expect2 = mix(viewPos, sv, 0.66);
            float blocked = max(step(0.20, expect1.z - v1.z), step(0.20, expect2.z - v2.z));
            // Facing term: surfaces pointing away from the emitter get no light
            float facing = clamp(dot(normal, diff / max(dist, 1e-4)), 0.0, 1.0);
            emisLight += sAlbedo * near * 2.4 * facing * (1.0 - blocked);
        } else {
            bounce += sAlbedo * occ;
        }
    }
    ao = clamp(1.0 - ao / float(SAMPLES) * 2.2 * SSAO_STRENGTH, 0.0, 1.0);
    bounce = bounce / float(SAMPLES) * 2.0 * GI_STRENGTH;
    emisLight = emisLight / float(SAMPLES) * 1.8 * GI_STRENGTH;
}

float contactShadow(vec3 viewPos, vec3 lightDirV) {
    float res = 1.0;
    vec3 rayStep = lightDirV * 0.08;
    vec3 p = viewPos + rayStep * (0.5 + ign(gl_FragCoord.xy));
    for (int i = 0; i < 8; i++) {
        p += rayStep;
        vec4 clip = gbufferProjection * vec4(p, 1.0);
        vec2 uv = clip.xy / clip.w * 0.5 + 0.5;
        if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) break;
        float sd = texture2D(depthtex0, uv).r;
        vec3 sv = getViewPos(uv, sd);
        float diff = p.z - sv.z;
        if (diff < -0.02 && diff > -0.35) { res = 0.2; break; }
    }
    return res;
}

void main() {
    float depth = texture2D(depthtex0, texcoord).r;
    vec3 color = texture2D(colortex0, texcoord).rgb;

    if (depth >= 1.0) {
/* DRAWBUFFERS:0 */
        gl_FragData[0] = vec4(color, 1.0);
        return;
    }

    vec4 gdata = texture2D(colortex1, texcoord);
    vec3 normal = normalize(gdata.rgb * 2.0 - 1.0);
    float mat = gdata.a;
    vec4 lmData = texture2D(colortex5, texcoord);
    vec2 lm = lmData.rg;
    float smoothness = lmData.b;         // labPBR
    float f0 = max(lmData.a, 0.015);

    vec3 viewPos = getViewPos(texcoord, depth);
    vec3 lightDirV = normalize(shadowLightPosition);
    mat3 mvInv = mat3(gbufferModelView);
    vec3 sunW = normalize(normalize(sunPosition) * mvInv);
    float haze = HAZE_HUMIDITY * 0.5 + wetness * 0.7 + thunderStrength * 0.5;

    // --- direct sun/moon light ---
    float NoL = dot(normal, lightDirV);
    vec3 sunAmt = vec3(0.0);
    vec3 lightColor = vec3(0.0);
    vec3 skyAmbient;
    float skyVis;

#if defined DIM_NETHER
    // No sun: warm ambient glow from the nether atmosphere itself
    skyAmbient = srgbToLinear(fogColor) * 0.9 + vec3(0.10, 0.035, 0.02);
    skyVis = 1.0;
#elif defined DIM_END
    skyAmbient = vec3(0.055, 0.045, 0.075);
    skyVis = 1.0;
    lightColor = vec3(0.30, 0.28, 0.38);
    sunAmt = vec3(smoothstep(0.0, 0.3, NoL) * 0.6);
#else
    // Skylight gate: no direct sun where vanilla says sky can't reach (leak guard)
    vec3 shadow = vec3(0.0);
    float skyGate = smoothstep(0.25, 0.65, lm.y);
    if (NoL > 0.0 && skyGate > 0.0) {
        shadow = sampleShadow(viewPos, normal, NoL);
        #ifdef CONTACT_SHADOWS
        if (luminance(shadow) > 0.1) shadow *= contactShadow(viewPos, lightDirV);
        #endif
    }
    sunAmt = smoothstep(0.0, 0.25, NoL) * shadow * skyGate;

    bool day = sunW.y > -0.05;
    // Slightly tamed vs before — was overexposing midday scenes
    lightColor = day
        ? sunColor(sunW, haze) * 4.2 * SUN_INTENSITY
          + vec3(0.35, 0.42, 0.55) * smoothstep(-0.05, 0.25, sunW.y) * 0.35
        : vec3(0.045, 0.06, 0.10) * 0.8;
    lightColor *= 1.0 - rainStrength * 0.75 - thunderStrength * 0.15;

    // --- ambient sky light: stronger, but cubic falloff into caves ---
    vec3 tr;
    skyAmbient = skyScatter(vec3(0.0, 1.0, 0.0), day ? sunW : -sunW, haze, tr) * (day ? 0.7 : 0.012);
    skyAmbient = max(skyAmbient, vec3(0.006, 0.007, 0.011));
    skyVis = lm.y * lm.y * lm.y;
#endif

    float ao = 1.0; vec3 bounce = vec3(0.0); vec3 emisLight = vec3(0.0);
    #ifdef SSGI_ENABLED
    ssgi(viewPos, normal, ao, bounce, emisLight);
    #endif

    // --- blocklight: warm, tight falloff + screen-space emissive spill ---
    float torch = lm.x * lm.x;

    // Directional blocklight: light direction estimated from the lightmap
    // gradient, so faces pointing away from the source fall into shadow
    vec3 dPdx = dFdx(viewPos), dPdy = dFdy(viewPos);
    float dLdx = dFdx(lm.x), dLdy = dFdy(lm.x);
    vec3 gradL = dPdx * dLdx + dPdy * dLdy;
    float gradLen = length(gradL);
    float blockNoL = 1.0;
    if (gradLen > 1e-5 && lm.x > 0.05 && lm.x < 0.98) {
        vec3 toLight = normalize(gradL);
        // Harder falloff: faces away from the source drop to near-black
        blockNoL = clamp(dot(normal, toLight) * 0.85 + 0.15, 0.0, 1.0);
        blockNoL *= blockNoL;
        blockNoL = mix(1.0, blockNoL, clamp(gradLen * 400.0, 0.0, 1.0));
    }

    vec3 torchColor = vec3(1.0, 0.52, 0.22) * (torch * torch * 2.1 + torch * 0.3) * blockNoL;
    torchColor *= 1.0 + 0.04 * sin(frameTimeCounter * 9.0 + hash12(floor(texcoord * 40.0)) * 6.0);
    // Emissive spill is tinted by the emitter's own texture color
    vec3 blockLight = torchColor + emisLight * (0.4 + torch);
    blockLight *= ao; // occlusion hits blocklight harder → darker behind objects

    // --- lightning flash ---
    vec3 lightning = vec3(0.0);
    #ifdef LIGHTNING_FLASH
    if (thunderStrength > 0.0) {
        float t = frameTimeCounter;
        float strike = step(0.985, hash12(vec2(floor(t * 2.7), 7.13)));
        float flash = strike * exp(-fract(t * 2.7) * 9.0) * thunderStrength;
        lightning = vec3(0.75, 0.82, 1.0) * flash * 10.0 * (0.4 + 0.6 * lm.y);
    }
    #endif

    // --- wet surface darkening ---
    vec3 albedo = color;
    float wet = wetness * lm.y * smoothstep(0.6, 1.0, normal.y * 0.5 + 0.5);
    albedo *= 1.0 - wet * 0.35;
    vec3 wetSheen = skyAmbient * wet * 0.4 * pow(1.0 - abs(dot(normalize(-viewPos), normal)), 3.0);

#ifdef DIM_NETHER
    vec3 bounceTerm = bounce * skyAmbient * 1.2;
    blockLight *= 1.4; // lava/torches carry the nether
#else
    vec3 bounceTerm = bounce * lightColor * 0.35 * skyVis;
#endif

    vec3 lighting = lightColor * sunAmt
                  + skyAmbient * skyVis * ao * 2.4
                  + bounceTerm
                  + blockLight
                  + lightning
                  + vec3(0.004) * ao;     // faint floor — caves stay dark but readable

    // --- PBR specular (GGX) from sun + wet-boosted smoothness ---
    vec3 specular = vec3(0.0);
    float rough = 1.0 - min(smoothness + wet * 0.4, 0.98);
    if (luminance(sunAmt) > 0.001 && rough < 0.95) {
        vec3 V = normalize(-viewPos);
        vec3 H = normalize(lightDirV + V);
        float NoH = max(dot(normal, H), 0.0);
        float a2 = rough * rough; a2 *= a2;
        float d = NoH * NoH * (a2 - 1.0) + 1.0;
        float D = a2 / max(PI * d * d, 1e-4);
        float F = f0 + (1.0 - f0) * pow(1.0 - max(dot(H, V), 0.0), 5.0);
        specular = lightColor * sunAmt * D * F * 0.25;
        if (f0 > 0.9) specular *= albedo; // metals tint their reflection
    }

#if !defined DIM_NETHER && !defined DIM_END
    // Environment (sky) reflection for smooth PBR surfaces — polished
    // blocks and metals pick up the sky like they should
    if (smoothness > 0.45) {
        vec3 V = normalize(-viewPos);
        vec3 reflW = normalize(reflect(-V, normal) * mvInv);
        if (reflW.y > 0.0) {
            vec3 trE;
            vec3 env = skyScatter(reflW, sunW, haze, trE) * 2.0 * SUN_INTENSITY;
            float fres = f0 + (1.0 - f0) * pow(1.0 - max(dot(V, normal), 0.0), 5.0);
            float gloss = (smoothness - 0.45) / 0.55;
            vec3 envSpec = env * fres * gloss * gloss * skyVis;
            if (f0 > 0.9) envSpec *= albedo;
            specular += envSpec;
        }
    }
#endif

    color = albedo * lighting + specular + wetSheen;

    // Emissive surfaces: graded HDR glow (ore specks partial, lamps full)
    if (mat > 0.85) {
        float glow = smoothstep(0.855, 0.965, mat);
        float e = luminance(albedo);
        vec3 emisColor = albedo * (2.0 + e * 5.0) + albedo * lighting * 0.3;
        color = mix(color, emisColor, glow);
    }

/* DRAWBUFFERS:0 */
    gl_FragData[0] = vec4(color, 1.0);
}
