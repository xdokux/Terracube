#version 120

// Bloom //

#define BLOOM

//the quantity of Bloom you want
#define BLOOM_MULT  0.50          //  [0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.30 1.40 1.50 1.60 1.70 1.80 1.90 2.00 2.10 2.20 2.30 2.40 2.50 2.60 2.70 2.80 2.90 3.00 3.10 3.20 3.30 3.40 3.50 3.60 3.70 3.80 3.90 4.00]

//The Radius of the Blur part
#define BLOOM_RADIUS 0.001				//  [0.09 0.08 0.07 0.06 0.05 0.04 0.03 0.02 0.01 0.009 0.008 0.007 0.006 0.005 0.004 0.003 0.002 0.001 0.0009 0.0008 0.0007 0.0006 0.0005 0.0004  0.0003 0.0002 0.0001]



uniform sampler2D gcolor;

varying vec2 texcoord;



void main() {

    vec3 color = texture2D(gcolor, texcoord).rgb;

	// Bloom //
	// Credits to Akashii


  float rad  = BLOOM_RADIUS;
	float sc = 20.0;
	float blm_amount = 0.02 / 52.5 * BLOOM_MULT;
	int i = 0;
	float samples = 1;
	vec4 clr = vec4(0.0);
  
#ifdef BLOOM
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

    /* DRAWBUFFERS:0 */

	gl_FragData[0] = vec4(clamp(color, 0.0, 1.0), 1.0); //gcolor


}
