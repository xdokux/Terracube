#version 120

//#define CinematicBars

uniform sampler2D gcolor;
varying vec4 texcoord;

void main() {

    vec3 color = texture2D(gcolor, texcoord.st).rgb;	
    color.r = color.r*0.8;
	color.g = color.g*0.9;
	color.b = color.b*0.7;

    #ifdef CinematicBars
        float barHeight = 0.12;
        if(texcoord.y < barHeight || texcoord.y > 1.0 - barHeight) {
            color = vec3(0.0);
        }
    #endif

    gl_FragColor = vec4(color,1.0f);	
}
