#version 120

#define WaterColor vec3(0.15, 0.75, 0.85) // Cyan-blue aquatic water color

uniform sampler2D texture;
uniform vec3 cameraPosition;

varying vec2 texcoord;
varying vec4 glcolor;

void main() {
    // Sample base water texture color unmodified
    vec4 baseColor = texture2D(texture, texcoord) * glcolor;

    // Multiply by fixed water color tint
    baseColor.rgb *= WaterColor;

    // Fixed alpha for 10% transparency (90% visible)
    float alpha = 0.5;

    gl_FragData[0] = vec4(baseColor.rgb, alpha);
}
