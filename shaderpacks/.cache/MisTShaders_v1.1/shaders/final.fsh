#version 120

varying vec2 TexCoords;
varying vec4 texcoord;

uniform ivec2 eyeBrightnessSmooth;

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;

#define TONEMAPPING

#define ACES 1.0
#define CE 2.0
#define FILMIC 3.0
#define UNREAL 4.0
#define REINHARD 5.0

#define TONEMAP ACES  // [ACES CE FILMIC UNREAL REINHARD]

// Tone mapping functions
vec3 ACESToneMapping(vec3 color, float adapted_lum) {
	const float A = 2.51f;
	const float B = 0.03f;
	const float C = 2.43f;
	const float D = 0.59f;
	const float E = 0.14f;
	color *= adapted_lum;
	return (color * (A * color + B)) / (color * (C * color + D) + E);
}

vec3 CEToneMapping(vec3 color, float adapted_lum) {
    return 1 - exp(-adapted_lum * color);
}

vec3 filmic(vec3 x) {
  vec3 X = max(vec3(0.0), x - 0.004);
  vec3 result = (X * (8.8 * X + 0.8)) / (X * (6.8 * X + 2.0) + 0.17);
  return pow(result, vec3(2.2));
}

vec3 unreal(vec3 x) {
  return x / (7 + x) * 10;
}

vec3 reinhard(vec3 x) {
  return x / (0.5 + x);
}

void main() {
    vec3 Color = pow(texture2D(colortex0, TexCoords).rgb, vec3(1.0f / 2.2f));

    #ifdef TONEMAPPING
        if(TONEMAP == ACES) {
            Color.rgb = ACESToneMapping(Color.rgb, 1);
        }	
        if(TONEMAP == CE) {
            Color.rgb = CEToneMapping(Color.rgb, 1);
        }
        if(TONEMAP == FILMIC) {
            Color.rgb = filmic(Color.rgb);
        }
        if(TONEMAP == UNREAL) {
            Color.rgb = unreal(Color.rgb);
        }
        if(TONEMAP == REINHARD) {
            Color.rgb = reinhard(Color.rgb);
        }
    #endif

    gl_FragColor = vec4(Color, 1.0f);
}
