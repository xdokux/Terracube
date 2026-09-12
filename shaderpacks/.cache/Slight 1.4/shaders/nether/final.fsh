#version 330 compatibility

uniform sampler2D colortex0;
uniform sampler2D colortex4;

in vec2 texcoord;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

void main() {
    color = texture(colortex0, texcoord);

    vec4 refl = texture(colortex4, texcoord);
    color.rgb = mix(color.rgb, refl.rgb, refl.a);

    float lum = dot(color.rgb, vec3(0.2126, 0.7152, 0.0722));
    color.rgb = mix(color.rgb * vec3(0.8, 1.0, 1.2), color.rgb, smoothstep(0.0, 0.2, lum));

    float brightness = lum;

    float sat = mix(1.5, 1.0, smoothstep(0.5, 1.0, brightness));

    vec3 gray = vec3(lum);
    color.rgb = mix(gray, color.rgb, sat);

    color = 1.0 - exp(-color);
}