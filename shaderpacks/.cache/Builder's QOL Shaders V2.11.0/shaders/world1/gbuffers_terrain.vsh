#version 120

#define GRASS_AO //Adds ambient occlusion to tallgrass/flowers/etc... Works best with "Remove Y Offset" enabled.
#define HEAT_REFRACTION 1.00 //How much the screen jiggles around in the nether, or when in lava [0.00 0.25 0.50 0.75 1.00 1.25 1.50 1.75 2.00 2.25 2.50 2.75 3.00 3.25 3.50 3.75 4.00 4.25 4.50 4.75 5.00]
#define JUMPING_DRAGON_EGGS //Makes dragon eggs jump and wobble, as if they were about to hatch
#define LAVA_PATCHES //Randomizes lava brightness, similar to grass patches
//#define REMOVE_XZ_OFFSET //Removes random X/Z offset from tallgrass/flowers/etc...
//#define REMOVE_Y_OFFSET //Removes random Y offset from tallgrass/flowers/etc...

attribute vec2 mc_midTexCoord;
attribute vec3 mc_Entity;

uniform float frameTimeCounter;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform sampler2D noisetex;
uniform vec3 actualCameraPosition;

varying float ao;
varying float isLava;
varying vec2 lmcoord;
varying vec2 randCoord;
varying vec2 texcoord;
varying vec4 tint;

const int noiseTextureResolution = 256;
const float invNoiseRes = 1.0 / float(noiseTextureResolution);

const float lavaOverlayResolution                     = 24.0;

const float dragonEggJumpAttemptsPerSecond = 2.0;
const float dragonEggJumpSuccessChance     = 0.25;
const float dragonEggMinJumpAmount         = 0.25;
const float dragonEggMaxJumpAmount         = 0.5;
const float dragonEggJumpDecaySpeed        = 3.14159265359;
const float dragonEggRotationSpeed         = 4.0;

void main() {
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;

	vec3 vPosView = (gl_ModelViewMatrix * gl_Vertex).xyz;
	vec3 vPosPlayer = mat3(gbufferModelViewInverse) * vPosView;
	vec3 worldPos = vPosPlayer + actualCameraPosition;
	vec3 normal = gl_Normal;

	tint = gl_Color;

	ao = 1.0;
	isLava = 0.0;

	//Using IDs above 10000 to represent all blocks that I care about
	//if the ID is less than 10000, then I don't need to do extra logic to see if it has special effects.
	if (mc_Entity.x > 10000.0) {
		int id = int(mc_Entity.x) - 10000;
		if (id == 2 || id == 3 || id == 4) { //plants and double plants
			#ifdef GRASS_AO
				ao = float(texcoord.y < mc_midTexCoord.y);
				if (id != 2) ao = (ao + float(id == 4)) * 0.5;
			#endif

			#ifdef REMOVE_Y_OFFSET
				worldPos.y = floor(worldPos.y + 0.5);
			#endif
			#ifdef REMOVE_XZ_OFFSET
				worldPos.xz = floor(worldPos.xz + 0.5);
			#endif
		}

		#ifdef GRASS_AO
			else if (id == 5) { //crops
				ao = float(texcoord.y < mc_midTexCoord.y);
			}
		#endif

		#ifdef LAVA_PATCHES
			else if (id == 7 || id == 18) {
				isLava = 1.0;
				randCoord = (
					abs(gl_Normal.y) > 0.1
					? worldPos.xz * 2.0
					: vec2((worldPos.x + worldPos.z) * 4.0, worldPos.y + frameTimeCounter)
				);
			}
		#endif
		else if (id == 20) { //soul fire
			normal = vec3(0.0, 1.0, 0.0);

			lmcoord.x = 29.0 / 32.0;
		}
		#ifdef JUMPING_DRAGON_EGGS
			else if (id == 19) { //dragon eggs
				float jumpTime = frameTimeCounter * dragonEggJumpAttemptsPerSecond;
				float fracTime = fract(jumpTime);
				vec2 randomPos = vec2(fracTime - jumpTime, floor(jumpTime * invNoiseRes)) + vec2(0.5);
				vec3 jumpRandom = texture2D(noisetex, randomPos * invNoiseRes).rgb;
				if (jumpRandom.y < dragonEggJumpSuccessChance) {
					//find the block that the dragon egg is in.
					//this is possible because none of the dragon egg's
					//vertexes are actually on the edge of the block.
					//however, there are a few on the top and
					//bottom which are on the face of the block.
					//these vertexes are aligned using the
					//vertex's normal vector and texcoord.
					float fracY = fract(worldPos.y);
					vec3 centerPos;
					if (fracY == clamp(fracY, 0.03125, 0.96875)) {
						//normal vertex. position alone is enough to identify the center.
						centerPos = floor(worldPos);
					}
					else if (abs(gl_Normal.y) > 0.9) {
						//top or bottom face. use normals.
						centerPos = worldPos;
						centerPos.y -= gl_Normal.y * 0.25;
						centerPos = floor(centerPos);
					}
					else {
						//side directly connected to top or bottom. use texcoord.
						centerPos = worldPos;
						centerPos.y -= sign(mc_midTexCoord.y - texcoord.y) * 0.25;
						centerPos = floor(centerPos);
					}
					centerPos.xz += vec2(0.5);

					//determine how much the egg should jump, and in which direction.
					float yaw =
						jumpRandom.x * (3.14159265359 * 2.0)
						+ (jumpRandom.z - 0.5) * fracTime * dragonEggRotationSpeed;
					float reverseTime = 1.0 - fracTime;
					float pitch =
						mix(
							dragonEggMinJumpAmount,
							dragonEggMaxJumpAmount,
							jumpRandom.y / dragonEggJumpSuccessChance
						)
						* sin(-dragonEggJumpDecaySpeed * log2(reverseTime))
						* reverseTime;

					//create a rotation matrix to move the egg correctly.
					float x = cos(yaw);
					float z = sin(yaw);
					float xz = x * z;
					//the T in the following variables is short for "theta", which is a greek
					//letter often used in math to describe an angle or an amount of rotation.
					float sinT = sin(pitch);
					float cosT = cos(pitch);
					float invCosT = 1.0 - cosT;
					//this matrix was from the wikipedia page for "rotation matrix". it was then
					//simplified by removing unnecessary multiplications by 0, since y is always 0.
					mat3 jumpMatrix = mat3(
						cosT + x * x * invCosT,
						-z * sinT,
						xz * invCosT,

						z * sinT,
						cosT,
						-x * sinT,
						
						xz * invCosT,
						x * sinT,
						cosT + z * z * invCosT
					);

					//make the egg jump!
					vec3 relativePos = worldPos - centerPos;
					relativePos = jumpMatrix * relativePos;
					worldPos = relativePos + centerPos;

					//rotate normals too, because I can.
					normal = jumpMatrix * normal;
				}
			}
		#endif
	}

	vPosPlayer = worldPos - actualCameraPosition;
	vPosView = mat3(gbufferModelView) * vPosPlayer;
	gl_Position = gl_ProjectionMatrix * vec4(vPosView, 1.0);

	float glmult = dot(vec4(abs(normal.x), abs(normal.z), max(normal.y, 0.0), max(-normal.y, 0.0)), vec4(0.6, 0.8, 1.0, 0.5));
	glmult = mix(glmult, 1.0, lmcoord.x * lmcoord.x); //increase brightness when block light is high
	tint.rgb *= glmult;
}