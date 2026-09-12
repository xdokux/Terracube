#version 120

#define SHADOW_DARKNESS 0.35              // Shadow darkness [0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6]
#define SHADOW_PCF_RADIUS 1.0             // Shadow edge softness in texels [0.5 0.75 1.0 1.25 1.5 2.0 2.5]
#define COLORED_SHADOW_STRENGTH 1.0       // Stained-glass colored shadow strength [0.0 0.25 0.5 0.75 1.0]
#define BLOCK_LIGHT_BRIGHTNESS 1.4        // Torch/lantern/etc. brightness multiplier [0.8 1.0 1.2 1.4 1.6 1.8 2.0]

uniform sampler2D tex;
uniform sampler2D shadowtex0; // depth including translucent casters (e.g. stained glass)
uniform sampler2D shadowtex1; // depth of OPAQUE casters only
uniform sampler2D shadowcolor0; // tint color of translucent shadow casters
uniform vec3 shadowLightPosition;

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 vColor;
varying vec3 normal;
varying vec4 shadowPos;

// Returns a light color for one shadow-map tap:
//   vec3(SHADOW_DARKNESS) -> blocked by opaque geometry
//   tinted color           -> blocked only by translucent/colored glass
//   vec3(1.0)              -> fully lit
vec3 sampleShadowTap(vec2 uv, float compareDepth) {
    float bias = 0.0008;

    float solidDepth = texture2D(shadowtex1, uv).r;
    if (compareDepth - bias > solidDepth) {
        return vec3(SHADOW_DARKNESS);
    }

    float fullDepth = texture2D(shadowtex0, uv).r;
    if (compareDepth - bias > fullDepth) {
        // Nothing opaque is blocking, but something translucent is -
        // this is the stained-glass case. Tint using the color that
        // was written into shadowcolor0 during the shadow pass.
        vec3 tint = texture2D(shadowcolor0, uv).rgb;
        return mix(vec3(1.0), tint, COLORED_SHADOW_STRENGTH);
    }

    return vec3(1.0);
}

/* RENDERTARGETS: 0,1 */
void main() {
    vec4 albedo = texture2D(tex, texcoord) * vColor;
    if (albedo.a < 0.1) discard;

    // ---- 2x2 PCF, configurable radius, with colored-glass support ----
    vec3 shadowScreen = shadowPos.xyz / shadowPos.w;
    shadowScreen = shadowScreen * 0.5 + 0.5;

    vec3 shadowResult = vec3(1.0);
    if (shadowScreen.x >= 0.0 && shadowScreen.x <= 1.0 &&
        shadowScreen.y >= 0.0 && shadowScreen.y <= 1.0 &&
        shadowScreen.z >= 0.0 && shadowScreen.z <= 1.0) {

        float texelSize = (1.0 / 2048.0) * SHADOW_PCF_RADIUS;
        vec3 sum = vec3(0.0);
        sum += sampleShadowTap(shadowScreen.xy + vec2(-texelSize, -texelSize), shadowScreen.z);
        sum += sampleShadowTap(shadowScreen.xy + vec2( texelSize, -texelSize), shadowScreen.z);
        sum += sampleShadowTap(shadowScreen.xy + vec2(-texelSize,  texelSize), shadowScreen.z);
        sum += sampleShadowTap(shadowScreen.xy + vec2( texelSize,  texelSize), shadowScreen.z);
        shadowResult = sum * 0.25;
    }

    vec3 n = normalize(normal);
    float NdotL = clamp(dot(n, normalize(shadowLightPosition)), 0.0, 1.0);

    // BUGFIX: lmcoord.x/.y are (approximately - there's a small texel-
    // padding inaccuracy that's visually negligible) the raw block
    // light and sky light levels, 0-1 each, BEFORE being blended into
    // the pretty lightmap texture. Using them directly lets block
    // light (torches, lanterns, glowstone, lava...) be its own additive
    // term that the sun/shadow math never touches - which is what was
    // actually missing before. Only the sky/sun term is affected by
    // shadowResult and NdotL now, so colored glass correctly tints
    // sunlight specifically, not torchlight on the other side of a
    // wall from a window.
    float blockLight = clamp(lmcoord.x, 0.0, 1.0);
    float skyLight = clamp(lmcoord.y, 0.0, 1.0);

    vec3 blockLightColor = vec3(1.0, 0.75, 0.45);
    vec3 skyLightColor = vec3(0.8, 0.87, 1.0);

    vec3 blockContribution = blockLightColor * pow(blockLight, 1.5) * BLOCK_LIGHT_BRIGHTNESS;
    vec3 sunContribution = skyLightColor * skyLight * NdotL * shadowResult;
    vec3 ambientFloor = vec3(0.05); // small floor so fully unlit corners aren't pure black

    vec3 lighting = ambientFloor + blockContribution + sunContribution;
    vec3 finalColor = albedo.rgb * lighting;

    gl_FragData[0] = vec4(clamp(finalColor, 0.0, 1.0), albedo.a);
    gl_FragData[1] = vec4(n * 0.5 + 0.5, 0.0);
}
