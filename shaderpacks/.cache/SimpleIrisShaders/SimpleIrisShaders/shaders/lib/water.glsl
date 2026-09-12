/*
    water.glsl
    ---------------------------------------------------------------
    Vertex-based wave displacement for water. This runs once per
    vertex in gbuffers_water.vsh, NOT per fragment, which is why it's
    safe to leave enabled even on the igpu profile - a water plane
    has orders of magnitude fewer vertices than the fragments it
    covers on screen, so this is one of the cheapest visual upgrades
    in the whole pack per unit of "looks nicer."

    No reflections, no fragment-shader normal-map displacement, no
    screen-space anything here by design (per your scope cut).
    ---------------------------------------------------------------
*/
#ifndef WATER_GLSL
#define WATER_GLSL


#include "settings.glsl"

uniform float frameTimeCounter;

// worldPos is the vertex's world-space XZ (Y intentionally ignored
// for the frequency input so waves don't warp on vertical water
// faces). Returns a world-space Y offset to add to the vertex.
float waterWaveHeight(vec2 worldPosXZ) {
    float t = frameTimeCounter * WATER_WAVE_SPEED;

    // Two overlapping sine waves at different frequencies/directions
    // is enough to break up an obviously-repeating single sine wave
    // without needing a texture-based wave map (which would cost a
    // texture fetch per vertex for no real benefit at this scale).
    float wave1 = sin(worldPosXZ.x * 0.6 + worldPosXZ.y * 0.4 + t * 1.2);
    float wave2 = sin(worldPosXZ.x * 0.35 - worldPosXZ.y * 0.5 + t * 0.8 + 1.7);

    return (wave1 * 0.6 + wave2 * 0.4) * WATER_WAVE_HEIGHT;
}

#endif // WATER_GLSL
