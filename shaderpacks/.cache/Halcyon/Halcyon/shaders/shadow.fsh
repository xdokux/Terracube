#version 120

uniform sampler2D texture;

varying vec2 texcoord;
varying vec4 vertexColor;

/* RENDERTARGETS: 0 */

void main() {
    vec4 albedo = texture2D(texture, texcoord) * vertexColor;

    // Alpha-cutout geometry (leaves, etc.) should leave real holes in the shadow
    if (albedo.a < 0.1) discard;

    // Written to shadowcolor0. For opaque casters this is never read back
    // (the terrain/deferred shadow lookup short-circuits on shadowtex1 first -
    // see deferred.fsh), so it's only meaningful for translucent casters like
    // stained glass or water, where it tints the light passing through them.
    gl_FragData[0] = vec4(albedo.rgb, albedo.a);
}
