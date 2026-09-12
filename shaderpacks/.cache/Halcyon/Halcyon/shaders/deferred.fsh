#version 120

uniform sampler2D colortex0; // albedo
uniform sampler2D colortex1; // encoded normal
uniform sampler2D colortex2; // lightmap uv
uniform sampler2D depthtex0;
uniform sampler2D lightmap;  // vanilla torch/sky lightmap, precombined & tinted by the game

uniform sampler2D shadowtex0;   // depth incl. translucent casters
uniform sampler2D shadowtex1;   // depth of opaque casters only
uniform sampler2D shadowcolor0; // color/tint of translucent casters

uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowProjection;
uniform mat4 shadowModelView;

uniform vec3 shadowLightPosition;
uniform float rainStrength;

varying vec2 texcoord;

const float SHADOW_MAP_RES = 2048.0;

// Reconstructs the camera-relative world-space position of this fragment
// from the depth buffer. Same space gl_Vertex uses in the gbuffers programs.
vec3 reconstructPosition(float depth) {
    vec4 clipPos = vec4(texcoord * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 viewPosH = gbufferProjectionInverse * clipPos;
    vec3 viewPos = viewPosH.xyz / viewPosH.w;
    vec4 worldPosH = gbufferModelViewInverse * vec4(viewPos, 1.0);
    return worldPosH.xyz;
}

// Returns a light color multiplier: white where fully lit, black where blocked
// by opaque geometry, tinted where only blocked by colored translucent glass.
vec3 sampleColoredShadow(vec2 shadowUV, float shadowDepthZ) {
    float bias = 0.0015;

    float opaqueDepth = texture2D(shadowtex1, shadowUV).r;
    if (shadowDepthZ - bias > opaqueDepth) {
        return vec3(0.0);
    }

    float allDepth = texture2D(shadowtex0, shadowUV).r;
    if (shadowDepthZ - bias > allDepth) {
        vec4 tint = texture2D(shadowcolor0, shadowUV);
        return mix(vec3(1.0), tint.rgb, tint.a) * 0.75;
    }

    return vec3(1.0);
}

vec3 getShadow(vec3 feetPlayerPos) {
    vec4 shadowClip = shadowProjection * shadowModelView * vec4(feetPlayerPos, 1.0);
    vec3 shadowNDC = shadowClip.xyz / shadowClip.w * 0.5 + 0.5;

    if (shadowNDC.x < 0.0 || shadowNDC.x > 1.0 ||
        shadowNDC.y < 0.0 || shadowNDC.y > 1.0 ||
        shadowNDC.z > 1.0) {
        return vec3(1.0);
    }

    vec2 texelSize = vec2(1.0 / SHADOW_MAP_RES);
    vec3 shadow = vec3(0.0);
    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            shadow += sampleColoredShadow(shadowNDC.xy + vec2(x, y) * texelSize, shadowNDC.z);
        }
    }
    return shadow / 9.0;
}

void main() {
    float depth = texture2D(depthtex0, texcoord).r;
    vec4 marker = texture2D(colortex2, texcoord);

    // Nothing was drawn here by gbuffers_terrain (i.e. it's sky) - leave colortex0 untouched,
    // gbuffers_skybasic/skytextured already wrote the correct color for it.
    if (depth >= 1.0 || marker.a < 0.5) {
        gl_FragColor = texture2D(colortex0, texcoord);
        return;
    }

    vec3 albedo = texture2D(colortex0, texcoord).rgb;
    vec3 normal = normalize(texture2D(colortex1, texcoord).rgb * 2.0 - 1.0);
    vec2 lmcoord = marker.rg;

    vec3 feetPlayerPos = reconstructPosition(depth);

    float NdotL = max(dot(normal, normalize(shadowLightPosition)), 0.0);
    vec3 shadow = getShadow(feetPlayerPos);

    vec3 skyAmbient   = texture2D(lightmap, lmcoord).rgb; // vanilla torch+sky, already tinted for time of day
    vec3 directLight  = vec3(1.0, 0.96, 0.88) * NdotL * shadow * (1.0 - rainStrength * 0.6);

    vec3 litColor = albedo * (skyAmbient * 0.6 + directLight);

    gl_FragColor = vec4(litColor, 1.0);
}
