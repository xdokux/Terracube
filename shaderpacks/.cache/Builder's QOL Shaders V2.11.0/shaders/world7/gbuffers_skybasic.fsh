#version 120

#define TF_HORIZON_HEIGHT 0.05 //How far above the horizon the fog color will be applied [0.001 0.002 0.003 0.004 0.005 0.0075 0.01 0.02 0.03 0.04 0.05 0.075 0.1 0.2 0.3 0.4 0.5 0.75 1.0]

uniform float pixelSizeX;
uniform float pixelSizeY;
uniform mat4 gbufferModelView;
uniform mat4 gbufferProjectionInverse;
uniform vec3 fogColor;
uniform vec3 skyColor;

varying vec4 starData; //rgb = star color, a = flag for weather or not this pixel is a star.

float fogify(float x, float width) {
	//fast, vaguely bell curve-shaped function with variable width
	return width / (x * x + width);
}

vec3 calcFogColor(vec3 pos) {
	return mix(skyColor, fogColor, fogify(max(dot(pos, gbufferModelView[1].xyz), 0.0), TF_HORIZON_HEIGHT));
}

void main() {

/* DRAWBUFFERS:0 */
	gl_FragData[0] = starData.a > 0.9 ? starData : vec4(calcFogColor(normalize((gbufferProjectionInverse * vec4(gl_FragCoord.xy * vec2(pixelSizeX, pixelSizeY) * 2.0 - 1.0, 1.0, 1.0)).xyz)), 1.0); //gcolor
}