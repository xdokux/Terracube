#version 120

//#define CinematicBars
#define Saturation 1.0 //[0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5]
#define Exposure 1.0 //[0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5]

uniform sampler2D gcolor;
varying vec4 texcoord;

void main() {

    vec3 color = texture2D(gcolor, texcoord.st).rgb;	
    color.r = color.r*0.8;
	color.g = color.g*0.9;
	color.b = color.b*0.7;

    color *= Exposure;

    float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
    color = mix(vec3(luma), color, Saturation);

    #ifdef CinematicBars
        if (texcoord.y < 0.12 || texcoord.y > 0.88) {
            color = vec3(0.0);
        }
    #endif

    gl_FragColor = vec4(color,1.0f);	
}
