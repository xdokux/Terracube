/*
    gbuffers_terrain.vsh
    ---------------------------------------------------------------
    Pipeline stage: GBUFFERS_TERRAIN (opaque block geometry)
    Reads: vanilla vertex attributes (position, uv, lightmap, normal)
    Writes: interpolated data forward to gbuffers_terrain.fsh

    This pack is forward-shaded (no deferred G-buffer + separate
    lighting pass) - terrain is lit directly in its own fragment
    shader. That's a deliberate simplicity/performance choice: a
    deferred pass buys flexibility (many light sources, screen-space
    effects) we don't need for "sun + shadows + fog", at the cost of
    extra full-screen buffer writes/reads that integrated GPUs feel
    much more than discrete GPUs do.
    ---------------------------------------------------------------
*/
#version 330 compatibility

varying vec2 texCoord;
varying vec2 lightMapCoord;
varying vec3 normal;
varying vec3 viewPos;
varying vec4 vertexColor;

void main() {
    texCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lightMapCoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    normal = normalize(gl_NormalMatrix * gl_Normal);
    vertexColor = gl_Color;

    vec4 position = gl_ModelViewMatrix * gl_Vertex;
    viewPos = position.xyz;

    gl_Position = gl_ProjectionMatrix * position;
}
