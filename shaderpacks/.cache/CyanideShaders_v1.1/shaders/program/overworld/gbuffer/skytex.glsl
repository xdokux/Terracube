
#ifdef FRAGMENT_STAGE

uniform sampler2D       gcolor;

varying vec2            texcoord;

void main() {

    vec3 color              =   texture2D(gcolor, texcoord).rgb;

	// Brightness //

	float skyBSunrise 	    =   (4.0 * TimeSunrise);
	float skyBDay 		    =   (4.0 * TimeNoon);
	float skyBSunset 	    =   (4.0 * TimeSunset);
	float skyBMidnight      =   (4.0 * TimeMidnight);
    
	// Sky Color //

	vec3 scSunrise 		    =   vec3(0.90, 0.80, 0.10) * TimeSunrise / 5.0;
	vec3 scDay 			    =   vec3(1.00, 1.00, 1.07) * TimeNoon;
	vec3 scSunset 	        =   vec3(0.96, 0.70, 0.20) * TimeSunset / 5.0;
	vec3 scMidnight    	    =   vec3(0.00, 0.30, 0.46) * TimeMidnight;

	// Mix Brightness and Light color //

    float skyB              =   skyBSunrise + skyBDay + skyBSunset + skyBMidnight;
	vec3  skyColor 	        =   scSunrise + scDay + scSunset + (scMidnight);
	vec3  finalizeSky		=	skyB + skyColor;

    /* DRAWBUFFERS:0 */

	gl_FragData[0]      	=   vec4(clamp(color * finalizeSky, 0.0, 1.0), 1.0); //gcolor

}

#endif

#ifdef VERTEX_STAGE

varying vec2 texcoord;

void main() {
	gl_Position	 			= 	ftransform();
	texcoord 				= 	(gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
}

#endif