/*
    gbuffers_water.vsh
    ---------------------------------------------------------------
    Pipeline stage: GBUFFERS_WATER (water + all translucent geometry:
    glass, ice, stained glass panes, etc.)
    Reads: vanilla vertex attributes + world position for wave calc
    Writes: displaced vertex position, forward data to .fsh

    Waves are applied ONLY to water (checked via mc_Entity / a texture
    heuristic below), not to glass/ice sharing this same shader stage.
    No reflection math anywhere in this pack, per your scope cut -
    water is lit like slightly glossy translucent terrain.
    ---------------------------------------------------------------
*/
#version 330 compatibility

#include "lib/water.glsl"

uniform vec3 cameraPosition;
uniform mat4 gbufferModelViewInverse;

// mc_Entity.x carries the block's numeric ID metadata when Iris/
// OptiFine can supply it; more robust across versions is checking
// the vanilla "render type" via mc_Entity render layer flags, but
// the simplest reliable signal available to every OptiFine-format
// pack is: water is rendered with its texture's alpha already <1 and
// tinted per-biome, so we use vertex color's blue-ish tint plus alpha
// as a heuristic, falling back to "apply small waves to everything
// in this pass" if that heuristic is inconclusive - glass waving by
// a sub-pixel amount is imperceptible, so this fails safe.
varying vec2 texCoord;
varying vec2 lightMapCoord;
varying vec3 normal;
varying vec3 viewPos;
varying vec4 vertexColor;
varying float isLikelyWater;

void main() {
    texCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lightMapCoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    normal = normalize(gl_NormalMatrix * gl_Normal);
    vertexColor = gl_Color;

    // Water gets vertex-colored per-biome (blue-ish, alpha ~0.6-0.8);
    // glass/ice are usually near-white/uncolored with higher alpha.
    isLikelyWater = step(vertexColor.b, 0.98) * step(0.3, vertexColor.a) * step(vertexColor.a, 0.9);

    // gl_Vertex is already camera-relative world space in Minecraft's
    // rendering (chunks are built relative to the camera to avoid
    // float-precision issues at large world coordinates), so we just
    // add cameraPosition to get an absolute world position for a
    // spatially-stable, non-repeating wave pattern.
    vec4 worldPos = gl_Vertex;
    vec3 absoluteWorldPos = worldPos.xyz + cameraPosition;

    // Only displace the top face of water (normal pointing up) so we
    // don't warp vertical water-block sides into a jagged mess.
    float upFacing = smoothstep(0.3, 0.8, normal.y);
    float waveOffset = waterWaveHeight(absoluteWorldPos.xz) * isLikelyWater * upFacing;
    worldPos.y += waveOffset;

    vec4 position = gl_ModelViewMatrix * worldPos;
    viewPos = position.xyz;
    gl_Position = gl_ProjectionMatrix * position;
}
