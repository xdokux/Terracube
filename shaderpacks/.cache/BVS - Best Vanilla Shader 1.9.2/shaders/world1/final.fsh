#version 130

//Shader by LoLip_p

#include "/settings.glsl"

varying vec2 TexCoords;

uniform float viewWidth, viewHeight;
uniform sampler2D colortex0;

void main() {
    vec3 color = texture2D(colortex0, TexCoords).rgb;

    // Apply saturation, brightness, and contrast
    float average = (color.r + color.g + color.b) / 3.0;
    color.rgb = mix(vec3(average), color.rgb, SATURATION);
    color.rgb += BRIGHTNESS;
    color.rgb = ((color.rgb - 0.5) * CONTRAST) + 0.5;

    gl_FragColor.rgb = pow(color, vec3(0.8));
}
