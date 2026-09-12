#version 120

uniform sampler2D clouds;          // Your clouds.png
uniform float far;
uniform vec3 fogColor;
uniform vec3 skyColor;
uniform vec3 sunDirection;
uniform float frameTimeCounter;    // For cloud animation
uniform int CloudToggle;           // 0 = OFF, 1 = ON

varying vec3 wPos;

/* Glow effect for clouds near the sun */
vec3 cloudGlow(float sunFactor) {
    return mix(vec3(1.0), vec3(1.5, 1.4, 1.2), sunFactor) * 1.8;
}

void main() {
    if (CloudToggle == 0) {
        discard; // Skip clouds if disabled
        return;
    }

    // Animate clouds along X axis
    vec2 uv = wPos.xz * 0.001 + vec2(frameTimeCounter * 0.0003, 0.0);
    uv = fract(uv); // Repeat texture

    // Sample your clouds texture
    vec4 cloudTex = texture2D(clouds, uv);

    // Sun glow effect
    float sunFactor = max(dot(normalize(wPos), sunDirection), 0.0);
    vec3 cloudLighting = cloudGlow(sunFactor);

    // Combine texture and sun glow
    vec3 cloudColor = mix(cloudTex.rgb, cloudLighting, cloudTex.a);

    // Blend slightly with fog for realism
    cloudColor = mix(cloudColor, fogColor, 0.1);

    gl_FragColor = vec4(cloudColor, 1.0);
}
