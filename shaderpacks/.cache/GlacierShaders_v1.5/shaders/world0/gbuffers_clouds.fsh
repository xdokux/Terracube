#version 120

uniform float far;
uniform vec3 fogColor;
uniform vec3 skyColor;
uniform vec3 sunDirection;
uniform int CloudToggle; // 0 = OFF, 1 = ON

varying vec3 wPos;

/* Simple noise function for smooth clouds */
float smoothNoise(vec2 uv) {
    return fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453);
}

/* Soft cloud density function */
float cloudDensity(vec3 pos) {
    float noise1 = smoothNoise(pos.xz * 0.08);
    float noise2 = smoothNoise(pos.xz * 0.04) * 0.5;
    float density = smoothstep(0.5, 0.9, noise1 + noise2); // Ensures soft clouds
    return pow(density, 1.2); // Slight contrast boost
}

/* Glow effect for clouds near the sun */
vec3 cloudGlow(float sunFactor) {
    return mix(vec3(1.0), vec3(1.5, 1.4, 1.2), sunFactor) * 1.8;
}

/* DRAWBUFFERS:0 */
void main() {
    if (CloudToggle == 0) {
        discard; // Skip rendering clouds
        return;
    }

    // Compute cloud density
    float density = cloudDensity(wPos) * 2.0;
    density = clamp(density, 0.9, 1.0); // Force pure white clouds

    // Sun glow effect
    float sunFactor = max(dot(normalize(wPos), sunDirection), 0.0);
    vec3 cloudLighting = cloudGlow(sunFactor);

    // Final cloud color (pure white with glow)
    vec3 cloudColor = mix(vec3(1.0), cloudLighting, density * 1.1);

    // Prevent fog from darkening clouds
    cloudColor = mix(cloudColor, vec3(1.0), smoothstep(0.0, far * 0.2, length(wPos.xz)));

    gl_FragColor = vec4(cloudColor, 1.0); // Fully solid white clouds
}
