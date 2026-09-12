#version 120

uniform vec3 sunPosition;
uniform vec3 upPosition;
uniform float rainStrength;
uniform float frameTimeCounter;

varying vec4 vertexColor;
varying vec3 viewDir;

// --- tunable cloud constants ---
const float CLOUD_HEIGHT_SCALE = 1.8;
const float CLOUD_SPEED = 0.006;
const float CLOUD_COVERAGE = 0.55; // higher = more cloud

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float valueNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

float fbm(vec2 p) {
    float value = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 5; i++) {
        value += amp * valueNoise(p);
        p *= 2.0;
        amp *= 0.5;
    }
    return value;
}

void main() {
    vec3 up = normalize(upPosition);
    float heightFactor = clamp(dot(viewDir, up) * 0.5 + 0.5, 0.0, 1.0);

    vec3 zenithColor  = mix(vec3(0.25, 0.45, 0.85), vec3(0.02, 0.03, 0.08), rainStrength);
    vec3 horizonColor = mix(vec3(0.65, 0.75, 0.90), vec3(0.15, 0.16, 0.20), rainStrength);

    float sunHeight = dot(normalize(sunPosition), up);
    float sunset = 1.0 - clamp(abs(sunHeight) * 4.0, 0.0, 1.0);
    horizonColor = mix(horizonColor, vec3(0.9, 0.55, 0.35), sunset * (1.0 - rainStrength));

    vec3 skyGradient = mix(horizonColor, zenithColor, heightFactor);

    // --- procedural clouds, projected onto a flat plane above the camera ---
    vec3 cloudColor = skyGradient;
    if (viewDir.y > 0.0 || dot(viewDir, up) > 0.02) {
        vec3 right = normalize(cross(up, vec3(0.0, 0.0, 1.0)));
        vec3 forward = cross(right, up);

        float upComponent = max(dot(viewDir, up), 0.05);
        vec2 cloudUV = vec2(dot(viewDir, right), dot(viewDir, forward)) / upComponent;
        cloudUV = cloudUV * CLOUD_HEIGHT_SCALE + frameTimeCounter * CLOUD_SPEED;

        float density = fbm(cloudUV);
        density = smoothstep(CLOUD_COVERAGE, CLOUD_COVERAGE + 0.25, density);

        vec3 litCloud = mix(vec3(0.5, 0.5, 0.55), vec3(1.0, 0.98, 0.92), 1.0 - sunset * 0.5);
        litCloud = mix(litCloud, vec3(0.35, 0.35, 0.4), rainStrength);

        // Fade clouds out near the horizon so the flat-plane projection doesn't
        // stretch into obviously wrong shapes at grazing angles.
        float edgeFade = smoothstep(0.02, 0.15, dot(viewDir, up));
        cloudColor = mix(skyGradient, litCloud, density * edgeFade);
    }

    vec3 finalColor = mix(cloudColor, vertexColor.rgb, vertexColor.a);
    gl_FragColor = vec4(finalColor, 1.0);
}
