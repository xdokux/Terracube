
#ifdef FRAGMENT_STAGE

uniform sampler2D       gcolor;

varying vec2            texcoord;

// Tonemapping //
// Credits to Akashii for Filmic Tonemapping

#if TONEMAPPING == 1
vec3 tonemapFilmic(vec3 x) {

	vec3 X				= 	max(vec3(0.0), x - 0.004);
  	vec3 result 		= 	(X * (6.2 * X + 0.5)) / (X * (6.2 * X + 1.7) + 0.06);
  	return pow(result, vec3(2.2));

}
#elif TONEMAPPING == 2
vec3 Uncharted2Tonemap(vec3 x) {

	float A = 0.2;
	float B = 0.35;
	float C = 0.07;
	float D = 0.09;		
	float E = 0.02;
	float F = 0.3;
	float W = 48.0;

	return ((x * (A * x + C * B) + D * E) / (x * (A * x + B) + D * F)) - E / F;
}
#elif TONEMAPPING == 3
vec3 tonemapACESapprox(vec3 v) {

    v *= 0.6f;
    float a = 2.51f;
    float b = 0.03f;
    float c = 2.43f;
    float d = 0.59f;
    float e = 0.14f;
    return clamp((v * (a * v + b)) / (v * (c * v + d) + e), 0.0f, 1.0f);
}
#elif TONEMAPPING == 4
vec3 tonemapReinhard(vec3 v) {

    return v / (1.0f + v);
}
#endif

void main() {

    vec3 color              =   texture2D(gcolor, texcoord).rgb;

	// Bloom //
	// Credits to Akashii
	
	#ifdef BLOOM
    float rad 				= 0.001; 
	float sc 				= 20.0;
	float blm_amount 		= 0.02 / 52.5 * BLOOM_MULT;
	int i 					= 0; 
	float samples 			= 1; 
	vec4 clr 				= vec4(0.0);
	
	for (i = -8; i < 8; i++) {
	vec2 d = vec2(-i, i), e = vec2(0, i), f = texcoord.st;

	clr += texture2D(gcolor, f + ( d.yy ) * rad) * sc;
	clr += texture2D(gcolor, f + ( d.yx ) * rad) * sc;
	clr += texture2D(gcolor, f + ( d.xy ) * rad) * sc;
	clr += texture2D(gcolor, f + ( d.xx ) * rad) * sc;

	clr += texture2D(gcolor, f + ( e.xy ) * rad) * sc;
	clr += texture2D(gcolor, f + (-e.yx ) * rad) * sc;
	clr += texture2D(gcolor, f + (-e.xy ) * rad) * sc;
	clr += texture2D(gcolor, f + ( e.yx ) * rad) * sc;

	++samples;
	sc = sc - 1.0;
	}
	clr = (clr / 8.0) / samples; color.rgb += clr.rgb / 52.5 * BLOOM_MULT;
	#endif

	// Brightness //

	float colorBSunrise 	=   BSUNRISE * (TimeSunrise);
	float colorBDay 		=   BDAY * (TimeNoon);
	float colorBSunset 	    =   BSUNSET * (TimeSunset);
	float colorBMidnight    =   BNIGHT * (TimeMidnight);

	// Sunlight/Moonlight Color //

	vec3 colorSunrise 		=   vec3(RLRISE, GLRISE, BLRISE) * TimeSunrise;
	vec3 colorDay 			=   vec3(RLDAY, GLDAY, BLDAY) * TimeNoon;
	vec3 colorSunset 	    =   vec3(RLSET, GLSET, BLSET) * TimeSunset;
	vec3 colorMidnight    	=   vec3(RLNIGHT, GLNIGHT, BLNIGHT) * TimeMidnight;

	// Mix Brightness and Light color //

	float colorB 	    	=   colorBSunrise + colorBDay + colorBSunset + colorBMidnight / 5.0;
	vec3 lightColor 	    =   colorSunrise + colorDay + colorSunset + (colorMidnight);
	vec3 mixBT				=	colorB + lightColor;

	// Tonemapping //

	#if TONEMAPPING == 1
	color.rgb 				= 	tonemapFilmic(color.rgb);
	#elif TONEMAPPING == 2
	vec3 Uncharted 			= 	Uncharted2Tonemap(color);
	vec3 WhiteScale 		= 	1.0f / Uncharted2Tonemap (vec3(48.0));
	color.rgb 				= 	pow(Uncharted * WhiteScale, vec3(1.0 / 2.2));
	#elif TONEMAPPING == 3
	color.rgb 				= 	tonemapACESapprox(color.rgb);
	#elif TONEMAPPING == 4
	color.rgb				=	tonemapReinhard(color.rgb);
	#endif

    /* DRAWBUFFERS:0 */

	gl_FragData[0]      	=   vec4(clamp(color * mixBT, 0.0, 1.0), 1.0); //gcolor

}

#endif



#ifdef VERTEX_STAGE

varying vec2 texcoord;

void main() {
	gl_Position	 			= 	ftransform();
	texcoord 				= 	(gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
}

#endif