#version 120

// This output (gl_FragColor) is what becomes "shadowcolor0" - the
// stored tint of translucent shadow casters like stained glass. The
// main gbuffers_terrain.fsh / gbuffers_water.fsh shaders read this
// buffer back to color light passing through colored glass.

uniform sampler2D tex;

varying vec2 texcoord;
varying vec4 vColor;

void main() {
    vec4 color = texture2D(tex, texcoord) * vColor;
    // Alpha-test so leaves/glass/foliage don't cast solid black shadows
    if (color.a < 0.1) discard;

    gl_FragColor = color;
}
