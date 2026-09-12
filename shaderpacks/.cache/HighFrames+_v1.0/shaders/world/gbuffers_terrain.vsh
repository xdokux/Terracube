#version 330 compatibility

// --- [ Foliage ] ---
#define FOLIAGE_WAVE 1 // [off on]
#define WAVE_SPEED 2.0 // [0.5 1.0 1.5 2.0 2.5 3.0 4.0]
#define WAVE_AMOUNT 0.03 // [0.01 0.02 0.03 0.04 0.05 0.08 0.1]

out float mask;
out float emission;
out vec2 lmcoord;
out vec2 texcoord;
out vec3 normal;
out vec4 glcolor;

uniform mat4 gbufferModelViewInverse;
uniform float frameTimeCounter;

in vec2 mc_Entity;
in vec4 at_midBlock;

void main() {
	gl_Position = ftransform();
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;

	lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
	lmcoord = lmcoord / (30.0 / 32.0) - (1.0 / 32.0);

	normal = gl_NormalMatrix * gl_Normal;
	normal = mat3(gbufferModelViewInverse) * normal;

	emission = at_midBlock.w;
    mask = mc_Entity.x;

	#if FOLIAGE_WAVE == 1
		if (abs(mask - 1.0) < 0.1) {
			vec4 pos = gl_Vertex;
			float t = frameTimeCounter;

			float wave = sin(t * WAVE_SPEED * 1.5 + pos.x * 0.8 + pos.z * 0.8) * WAVE_AMOUNT;
			float wave2 = sin(t * WAVE_SPEED * 2.3 + pos.x * 1.2 + pos.z * 0.5) * WAVE_AMOUNT * 0.5;

			pos.x += wave;
			pos.y += wave2;

			gl_Position = gl_ModelViewProjectionMatrix * pos;
		}
	#endif

	glcolor = gl_Color;
}
