#version 120 compatibility
#define gbuffers_terrain

uniform sampler2D texture;
uniform int isEyeInWater;
uniform vec3 fogColor;

varying vec4 color;
varying vec2 texcoord;
varying vec2 lmcoord;

void main() {
    vec4 texColor = texture2D(texture, texcoord);
    vec4 finalColor = texColor * color;

    float fog = (isEyeInWater > 0)
              ? 1.0 - exp(-gl_FogFragCoord * gl_Fog.density)
              : clamp((gl_FogFragCoord - gl_Fog.start) * gl_Fog.scale, 0.0, 1.0);

    gl_FragData[0] = mix(finalColor, vec4(fogColor, finalColor.a), fog);
}