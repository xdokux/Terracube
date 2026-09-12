#version 330 compatibility

// --- [ Color Grading ] ---
#define SATURATION 1.3 // [0.0 0.5 0.8 1.0 1.2 1.3 1.5 2.0 3.0]
#define EXPOSURE 1.0 // [0.5 0.7 0.8 1.0 1.2 1.5 2.0 3.0]
#define RED_TINT 1.2 // [0.5 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.5]
#define GREEN_TINT 1.05 // [0.5 0.7 0.8 0.9 1.0 1.05 1.1 1.2 1.3 1.5]
#define BLUE_TINT 1.0 // [0.5 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.5]

// --- [ Effects ] ---
#define LETTERBOX 0 // [0 1]

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
    color.rgb = mix(color.rgb * vec3(0.4, 0.85, 1.5), color.rgb, smoothstep(0.0, 0.2, lum));

    float brightness = lum;

    float sat = mix(SATURATION, 1.0, smoothstep(0.5, 1.0, brightness));

    vec3 gray = vec3(lum);
    color.rgb = mix(gray, color.rgb, sat);

    color = 1.0 - exp(-color * EXPOSURE);

    color.rgb *= vec3(RED_TINT, GREEN_TINT, BLUE_TINT);

    #if LETTERBOX == 1
        float barSize = 0.1;
        if (texcoord.y < barSize || texcoord.y > 1.0 - barSize) {
            color = vec4(0.0, 0.0, 0.0, 1.0);
        }
    #endif
}
