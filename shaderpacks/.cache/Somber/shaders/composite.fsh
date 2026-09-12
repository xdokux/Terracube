#version 330 compatibility

#define fogToggle
#define fogStrenth 0.993 // [0.95 0.96 0.97 0.98 0.99 0.992 0.993 0.994 0.995 0.996 0.997 0.998 0.999 0.9999 0.99999]
#define fogSkyOverlap

uniform sampler2D colortex0;
uniform sampler2D depthtex0;
uniform vec3 skyColor;
uniform float fogEnd;
uniform float fogStart;
uniform float eyeAltitude;

in vec2 texcoord;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

void main() {    

    vec4 outputColor = texture(colortex0, texcoord);

    #ifdef fogToggle
        float depth = texture(depthtex0, texcoord).r;

        #ifndef fogSkyOverlap
            if (depth < 1.0) {
                vec3 caveFactor = skyColor - smoothstep(80.0, 0.0, eyeAltitude);
                outputColor.rgb = mix(outputColor.rgb, caveFactor, smoothstep(fogStrenth, 1.0, depth));
            }
        #endif

        #ifdef fogSkyOverlap
                vec3 caveFactor = skyColor - smoothstep(80.0, 0.0, eyeAltitude);
                outputColor.rgb = mix(outputColor.rgb, caveFactor, smoothstep(fogStrenth, 1.0, depth));
        #endif


    #endif

    
    color = vec4(outputColor);
}
