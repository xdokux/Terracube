#version 120

uniform float viewHeight;
uniform float viewWidth;
uniform mat4 gbufferModelView;
uniform mat4 gbufferProjectionInverse;
uniform vec3 fogColor;

varying vec4 starData; // rgb = star color, a = flag for stars

float fogify(float x, float w) {
    return w / (x * x + w);
}

vec3 calcSkyColor(vec3 pos) {
    float upDot = dot(pos, gbufferModelView[1].xyz);
    float horizonFactor = pow(max(upDot, 0.0), 0.5);

    // Zenith: deep rich blue
    vec3 zenithColor = vec3(0.05, 0.15, 0.55);
    // Mid: vivid blue
    vec3 midColor = vec3(0.15, 0.45, 0.90);
    // Horizon: bright cyan
    vec3 horizonColor = vec3(0.35, 0.75, 0.95);

    // Two-stop gradient: zenith->mid in upper sky, mid->horizon near horizon
    vec3 color;
    if (upDot > 0.35) {
        // Upper sky: deep blue to vivid blue
        float t = (upDot - 0.35) / 0.65;
        color = mix(midColor, zenithColor, t);
    } else {
        // Lower sky: vivid blue to cyan horizon
        float t = upDot / 0.35;
        color = mix(horizonColor, midColor, smoothstep(0.0, 1.0, t));
    }

    return mix(color, fogColor, fogify(max(upDot, 0.0), 0.2));
}

void main() {
    vec3 color;
    if (starData.a > 0.5) {
        color = starData.rgb; // stars remain unchanged
    } else {
        vec4 pos = vec4(gl_FragCoord.xy / vec2(viewWidth, viewHeight) * 2.0 - 1.0, 1.0, 1.0);
        pos = gbufferProjectionInverse * pos;
        color = calcSkyColor(normalize(pos.xyz));
    }

    gl_FragData[0] = vec4(color, 1.0);
}
