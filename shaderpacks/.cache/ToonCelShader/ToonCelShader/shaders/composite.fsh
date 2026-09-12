/*
    composite.fsh - the outline pass.
    Reads: colortex0 (toon-shaded color), colortex1 (view-space
           normal, written 0..1 remapped by the gbuffers_* stages),
           depthtex0 (scene depth)

    This is a classic screen-space edge-detection outline (the same
    core idea used by real cel-shaded games): compare each pixel's
    depth and normal against its neighbors. A big jump in either one
    means there's a silhouette or hard-corner edge there, so paint it
    with OUTLINE_COLOR. Depth alone would miss edges between two
    coplanar-but-differently-angled surfaces (like a block corner
    facing the camera at 45 degrees); normal alone would miss edges
    where depth changes but normals happen to match (like a thin
    object in front of a flat wall) - using both catches what either
    one misses on its own.
*/
#version 330 compatibility

#include "lib/settings.glsl"

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D depthtex0;
uniform vec2 screenSize;

varying vec2 texCoord;

void main() {
    vec3 color = texture2D(colortex0, texCoord).rgb;

#if OUTLINES == 1
    vec2 texel = (1.0 / screenSize) * OUTLINE_THICKNESS;

    float depthCenter = texture2D(depthtex0, texCoord).r;
    vec3 normalCenter = texture2D(colortex1, texCoord).rgb * 2.0 - 1.0;

    float depthLeft  = texture2D(depthtex0, texCoord - vec2(texel.x, 0.0)).r;
    float depthRight = texture2D(depthtex0, texCoord + vec2(texel.x, 0.0)).r;
    float depthUp    = texture2D(depthtex0, texCoord + vec2(0.0, texel.y)).r;
    float depthDown  = texture2D(depthtex0, texCoord - vec2(0.0, texel.y)).r;

    vec3 normalLeft  = texture2D(colortex1, texCoord - vec2(texel.x, 0.0)).rgb * 2.0 - 1.0;
    vec3 normalRight = texture2D(colortex1, texCoord + vec2(texel.x, 0.0)).rgb * 2.0 - 1.0;
    vec3 normalUp    = texture2D(colortex1, texCoord + vec2(0.0, texel.y)).rgb * 2.0 - 1.0;
    vec3 normalDown  = texture2D(colortex1, texCoord - vec2(0.0, texel.y)).rgb * 2.0 - 1.0;

    // Depth is stored non-linearly, so a fixed threshold naturally
    // catches close-up edges more easily than distant ones - which
    // is actually the right behavior here (distant outlines would be
    // sub-pixel noise anyway).
    float depthDiff = abs(depthLeft - depthRight) + abs(depthUp - depthDown);
    float depthEdge = step(0.0006 / OUTLINE_DEPTH_SENSITIVITY, depthDiff);

    float normalDiff = (1.0 - dot(normalCenter, normalLeft))
                      + (1.0 - dot(normalCenter, normalRight))
                      + (1.0 - dot(normalCenter, normalUp))
                      + (1.0 - dot(normalCenter, normalDown));
    float normalEdge = step(OUTLINE_NORMAL_SENSITIVITY, normalDiff);

    // Never draw an outline against the sky (depth == 1.0 on both
    // sides) - otherwise every silhouette against open sky gets a
    // heavy, ugly double-thick line from the sky's own "flatness".
    float isSky = step(0.9999, depthCenter);

    float edge = max(depthEdge, normalEdge) * (1.0 - isSky);
    color = mix(color, OUTLINE_COLOR, edge);
#endif

    gl_FragColor = vec4(color, 1.0);
}
