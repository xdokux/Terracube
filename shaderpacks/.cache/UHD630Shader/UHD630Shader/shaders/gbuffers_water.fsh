#version 120
/* DRAWBUFFERS:01 */

varying vec3 normal;
varying vec4 color;
varying vec2 texcoord;
varying vec4 worldPos;

uniform sampler2D texture;
uniform float frameTimeCounter;

void main() {
    vec4 albedo = texture2D(texture, texcoord) * color;

    // Cheap wave perturbation: two sine terms, no extra texture sample (no normal map).
    // This is intentionally crude - a real wave normal map would look better but costs
    // a texture fetch per water pixel, which adds up on shared-memory graphics.
    vec3 waveNormal = normal;
    waveNormal.x += sin(worldPos.x * 0.5 + frameTimeCounter * 1.3) * 0.06;
    waveNormal.z += cos(worldPos.z * 0.5 + frameTimeCounter * 1.1) * 0.06;
    waveNormal = normalize(waveNormal);

    gl_FragData[0] = vec4(albedo.rgb, 0.65); // semi-transparent water tint
    // Alpha channel = 1: "this pixel is reflective, do SSR on it in composite1".
    gl_FragData[1] = vec4(waveNormal * 0.5 + 0.5, 1.0);
}
