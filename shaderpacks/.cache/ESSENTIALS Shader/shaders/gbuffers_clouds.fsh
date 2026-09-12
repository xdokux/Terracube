#version 120

uniform float sunAngle;

varying vec2 texcoord;
varying vec4 glcolor;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
        mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x),
        f.y
    );
}

void main() {
    float timeOfDay = clamp(sin(sunAngle * 3.14159 * 2.0) * 3.0, 0.0, 1.0);
    float sunset    = clamp(1.0 - abs(timeOfDay - 0.5) * 6.0, 0.0, 1.0);

    vec3 dayColor    = vec3(1.0, 1.0, 1.0);
    vec3 nightColor  = vec3(0.08, 0.1, 0.18);
    vec3 sunsetColor = vec3(1.0, 0.55, 0.2);

    vec3 cloudColor  = mix(nightColor, dayColor, timeOfDay);
    cloudColor       = mix(cloudColor, sunsetColor, sunset * 0.7);

    float alpha = glcolor.a * mix(0.7, 1.0, timeOfDay);

    gl_FragData[0] = vec4(cloudColor, alpha);
}