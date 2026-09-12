/* ____    __   ______________
  / ______/ /  /  _/_  __/ __/
 / _//___/ /___/ /  / / / _/
/___/   /____/___/ /_/ /___/

E-LITE shaders 5 - Oscilator_utils.glsl #include "/lib/oscilator_utils.glsl"
Oscilation Synced with daytime (ticks) - Oscilação vinculada ao tempo mundial (ticks) */

uniform float hour_world;
uniform int worldDay;
float continuousWorldDay = mod(worldDay, 50.0);
float TotalWorldTime = hour_world + (continuousWorldDay * 24.0) - 1.0;

float oscillation(float Aux, float minval, float maxval, float speed) {
    float halfRange = (maxval - minval) * 0.5;
    float center = minval + halfRange;
    return center + sin(Aux * CLOUD_HI_FACTOR * speed) * halfRange;
}