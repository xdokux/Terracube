#version 120

#define WaterColor vec3(0.07, 0.5, 0.8) // Deep blue water color

uniform sampler2D texture;
uniform sampler2D lightmap;
uniform sampler2D noisetex;
uniform vec3 cameraPosition;
uniform mat4 gbufferModelViewInverse;
uniform int worldTime;
uniform float frameTimeCounter;

varying vec2 lmcoord;
varying vec2 texcoord;
varying vec4 glcolor;
varying vec3 cPos;
varying vec3 wPos;
varying float waterHeight;
varying vec3 normal;
varying vec4 positionInViewCoord;

/* Smooth wave function */
vec3 getWave(vec3 color, vec4 positionInWorldCoord) {
    float time = float(worldTime) / 800.0; // Slow & smooth waves
    vec2 coord = positionInWorldCoord.xz * 0.02; // Large-scale waves

    // Sinusoidal smooth waves
    float wave1 = sin(coord.x * 5.0 + time) * 0.02;
    float wave2 = cos(coord.y * 6.0 + time * 1.2) * 0.015;
    float noise = texture2D(noisetex, coord * 0.5 + time * 0.02).r * 0.02;

    float wave = wave1 + wave2 + noise;
    color += vec3(wave * 0.5); // Gentle distortion

    return color;
}

void main() {
    // Base color with lighting
    vec4 baseColor = texture2D(texture, texcoord) * glcolor;
    baseColor *= texture2D(lightmap, lmcoord);

    // Transform position to world coordinates
    vec4 positionInWorldCoord = gbufferModelViewInverse * positionInViewCoord;
    positionInWorldCoord.xyz += cameraPosition;

    // Apply soft wave effect
    vec3 finalColor = getWave(WaterColor, positionInWorldCoord);

    // **Depth-based blue tint**
    float depthFactor = clamp(waterHeight * 0.1, 0.5, 1.0);
    finalColor = mix(finalColor, WaterColor, depthFactor * 0.8);

    // **Gentle water reflections** (soft specular highlight)
    float lightFactor = max(dot(normal, vec3(0.0, 1.0, 0.0)), 0.0);
    finalColor += lightFactor * 0.05;

    // **30% More Transparency**
    float alpha = mix(0.2, 0.35, depthFactor); // Reduced opacity for a clearer look

    gl_FragData[0] = vec4(finalColor, alpha);
}
