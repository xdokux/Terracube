#version 120
/* DRAWBUFFERS:01 */
// Buffer 0 = final lit color, Buffer 1 = world-space normal (used later by SSR in composite1)

varying vec3 normal;
varying vec4 color;
varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 worldPos;

uniform sampler2D texture;
uniform sampler2D shadowtex1; // full shadow depth (includes alpha-tested foliage)

uniform mat4 shadowModelView;
uniform mat4 shadowProjection;

uniform vec3 shadowLightPosition; // sun or moon, whichever is up - provided by Iris

const float shadowBias = 0.0015;

// IMPORTANT: shadowModelView/shadowProjection operate in the SAME camera-relative
// space as gbufferModelView - do NOT add cameraPosition back in here. That was a
// bug in an earlier draft of this file; if you see shadows drifting or detached
// from geometry as you move away from world origin, this is the line to check.
float getShadow(vec3 relativeWorldPos) {
    vec4 shadowClip = shadowProjection * shadowModelView * vec4(relativeWorldPos, 1.0);
    vec3 shadowScreen = shadowClip.xyz * 0.5 + 0.5;

    if (shadowScreen.x < 0.0 || shadowScreen.x > 1.0 ||
        shadowScreen.y < 0.0 || shadowScreen.y > 1.0 ||
        shadowScreen.z > 1.0) {
        return 1.0; // outside shadow frustum -> fully lit
    }

    float shadowDepth = texture2D(shadowtex1, shadowScreen.xy).r;
    return (shadowScreen.z - shadowBias > shadowDepth) ? 0.35 : 1.0;
}

void main() {
    vec4 albedo = texture2D(texture, texcoord) * color;
    if (albedo.a < 0.1) discard;

    float shadow = getShadow(worldPos.xyz);

    float NdotL = clamp(dot(normalize(normal), normalize(shadowLightPosition)), 0.0, 1.0);
    float diffuse = mix(0.25, 1.0, NdotL) * shadow;

    // Blend directional lighting with vanilla block/sky lightmap so torches etc. still work.
    vec3 lit = albedo.rgb * diffuse * lmcoord.y;
    vec3 blockLight = albedo.rgb * lmcoord.x * 0.9;
    vec3 finalColor = max(lit, blockLight);

    gl_FragData[0] = vec4(finalColor, albedo.a);
    // Alpha channel of the normal buffer = 0 here: "this is not a reflective surface".
    gl_FragData[1] = vec4(normalize(normal) * 0.5 + 0.5, 0.0);
}
