#version 120

#define GRASS_AO //Adds ambient occlusion to tallgrass/flowers/etc... Works best with "Remove Y Offset" enabled.
#define GRASS_PATCHES //Makes grass less uniform by making patches of it dryer or lusher. Does not affect leaves.
#define HEAT_REFRACTION 1.00 //How much the screen jiggles around in the nether, or when in lava [0.00 0.25 0.50 0.75 1.00 1.25 1.50 1.75 2.00 2.25 2.50 2.75 3.00 3.25 3.50 3.75 4.00 4.25 4.50 4.75 5.00]
#define HUMIDITY_OFFSET 1.1 //Higher number = lusher grass. Lower number = dryer grass [0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0 1.05 1.1 1.15 1.2 1.25]
#define JUMPING_DRAGON_EGGS //Makes dragon eggs jump and wobble, as if they were about to hatch
#define LAVA_PATCHES //Randomizes lava brightness, similar to grass patches
//#define LEGACY_SUGARCANE //Removes biome coloring from sugar cane
//#define REMOVE_XZ_OFFSET //Removes random X/Z offset from tallgrass/flowers/etc...
//#define REMOVE_Y_OFFSET //Removes random Y offset from tallgrass/flowers/etc...
#define WATER_WAVE_STRENGTH 50 //Makes overworld oceans move up and down [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100]
#define WAVING_GRASS //Adds wind effects to grass
//#define WAVING_LEAVES //Adds wind effects to leaves
//#define WAVING_VINES //Adds wind effects to vines

attribute vec3 mc_Entity;
attribute vec4 mc_midTexCoord;

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

float lengthSquared2(vec2 v) { return dot(v, v); }

vec3 windOffset(vec3 pos, float multiplier, float speed) {
	float baseWindAmt = pos.y / 256.0 + 1.0; //1.0x at y=0, 2.0x at y=256
	vec3 waveStart = texture2D(noisetex, vec2(pos.x + frameTimeCounter, pos.z) * (0.375 * invNoiseRes)).rgb; //oscillation direction and phase offset
	float waveMultiplier = texture2D(noisetex, vec2(pos.x * 0.125 + frameTimeCounter * 0.5, pos.z * 0.125) * invNoiseRes).r * 0.5 + 0.5; //multiplier to add variety
	vec2 offset = vec2(waveStart.y * 0.4 - 0.2, waveStart.z * 0.2 - 0.1) * cos(waveStart.x * 6.283185307 + frameTimeCounter * speed) * waveMultiplier; //combine to get position offset
	offset.x -= baseWindAmt * 0.01 + 0.02; //biased towards east wind
	offset *= multiplier * baseWindAmt; //scale offset
	return vec3(offset.x, 0.5 / (lengthSquared2(offset) + 0.5) - 1.0, offset.y); //move vertexes down some based on how much they were offset
}

#ifdef GRASS_PATCHES
	float noiseMap(vec2 coord) {
		coord *= invNoiseRes;
		float noise = 0.0;
		noise += texture2D(noisetex, coord * 0.03125).r;
		noise += texture2D(noisetex, coord * 0.09375).r * 0.5;
		noise += texture2D(noisetex, coord * 0.375  ).r * 0.25;
		return noise;
	}
#endif

#if WATER_WAVE_STRENGTH != 0
	float waterWave(vec2 pos) {
		pos *= invNoiseRes;
		float offset = 0.875;
		offset += cos(texture2D(noisetex, pos / 20.0).r * 25.0 + frameTimeCounter * 2.0) * 0.5;
		offset += cos(texture2D(noisetex, pos / 15.0).r * 12.5 + frameTimeCounter * 3.0) * 0.375;
		return offset * (float(WATER_WAVE_STRENGTH) / 100.0 / 1.75);
	}
#endif

void main() {
	ao = 1.0;
	isLava = 0.0;

	bool isGrass = false;

	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;

	vec3 vPosView = (gl_ModelViewMatrix * gl_Vertex).xyz;
	vec3 vPosPlayer = mat3(gbufferModelViewInverse) * vPosView;
	vec3 worldPos = vPosPlayer + actualCameraPosition;
	vec3 normal = gl_Normal;

	tint = gl_Color;

	//Using IDs above 10000 to represent all blocks that I care about
	//if the ID is less than 10000, then I don't need to do extra logic to see if it has special effects.
	if (mc_Entity.x > 10000.0) {
		int id = int(mc_Entity.x) - 10000;
		if (id == 1) { //grass blocks and dirt
			#ifdef GRASS_PATCHES
				isGrass = gl_Color.g > gl_Color.b;
			#endif
		}
		else if (id == 2) { //tallgrass and other plants
			normal = vec3(0.0, 1.0, 0.0);

			#ifdef REMOVE_Y_OFFSET
				worldPos.y = floor(worldPos.y + 0.5);
			#endif
			#ifdef REMOVE_XZ_OFFSET
				worldPos.xz = floor(worldPos.xz + 0.5);
			#endif

			#if defined(GRASS_AO) || defined(WAVING_GRASS)
				float amt = float(texcoord.y < mc_midTexCoord.y);
				#ifdef GRASS_AO
					ao = amt;
				#endif

				#ifdef WAVING_GRASS
					if (amt > 0.1) { //will always either be 0.0 or 1.0
						worldPos += windOffset(worldPos, amt * lmcoord.y * lmcoord.y, 5.0);
					}
				#endif
			#endif

			#ifdef GRASS_PATCHES
				isGrass = gl_Color.g > gl_Color.b; //some double plants are colored by texture, and others are colored by biome.
			#endif
		}
		else if (id == 3 || id == 4) { //double plants
			normal = vec3(0.0, 1.0, 0.0);

			#ifdef REMOVE_Y_OFFSET
				worldPos.y = floor(worldPos.y + 0.5);
			#endif
			#ifdef REMOVE_XZ_OFFSET
				worldPos.xz = floor(worldPos.xz + 0.5);
			#endif

			#if defined(GRASS_AO) || defined(WAVING_GRASS)
				float amt = (float(texcoord.y < mc_midTexCoord.y) + float(id == 4)) * 0.5;
				#ifdef GRASS_AO
					ao = amt;
				#endif

				#ifdef WAVING_GRASS
					amt *= 1.5;
				#endif

				#ifdef WAVING_GRASS
					if (amt > 0.1) { //will always either be 0.0, 0.5 or 1.0
						worldPos += windOffset(worldPos, amt * lmcoord.y * lmcoord.y, 3.0);
					}
				#endif
			#endif

			#ifdef GRASS_PATCHES
				isGrass = gl_Color.g > gl_Color.b; //some double plants are colored by texture, and others are colored by biome.
			#endif
		}
		#ifdef WAVING_LEAVES
			else if (id == 13) { //leaves
				worldPos += windOffset(worldPos, lmcoord.y * lmcoord.y, 3.0);
			}
		#endif
		#ifdef WAVING_VINES
			else if (id == 14) { //vines
				worldPos += windOffset(worldPos, lmcoord.y * lmcoord.y, 3.0);
			}
		#endif
		else if (id == 5) { //crops
			normal = vec3(0.0, 1.0, 0.0);

			#ifdef GRASS_AO
				ao = float(texcoord.y < mc_midTexCoord.y);
			#endif

			#ifdef WAVING_GRASS
				if (texcoord.y < mc_midTexCoord.y) {
					worldPos += windOffset(worldPos, lmcoord.y * lmcoord.y, 5.0);
				}
			#endif
		}
		else if (id == 15) { //seagrass
			normal = vec3(0.0, 1.0, 0.0);

			#ifdef WAVING_GRASS
				if (texcoord.y < mc_midTexCoord.y) {
					worldPos += windOffset(worldPos, 1.0, 2.0);
				}
			#endif
		}
		else if (id == 16 || id == 17) { //tall seagrass
			normal = vec3(0.0, 1.0, 0.0);

			#ifdef WAVING_GRASS
				float amt = float(texcoord.y < mc_midTexCoord.y) + float(id == 17);
				if (amt > 0.1) { //will always either be 0.0, 0.5 or 1.0
					worldPos += windOffset(worldPos, amt, 1.0);
				}
			#endif
		}
		else if (id == 6) { //sugar cane
			normal = vec3(0.0, 1.0, 0.0);

			#ifdef LEGACY_SUGARCANE
				tint = vec4(1.0);
			#endif

			#ifdef GRASS_PATCHES
				isGrass = true;
			#endif
		}
		else if (id == 21) { //mushrooms and other sturdy plants
			normal = vec3(0.0, 1.0, 0.0);

			#ifdef GRASS_AO
				//mushrooms are kind of short, so multiply by 2
				//to make the AO start at half the block height.
				ao = float(texcoord.y < mc_midTexCoord.y) * 2.0;
			#endif
		}
		#ifdef LAVA_PATCHES
			else if (id == 7 || id == 18) { //lava
				isLava = 1.0;
				randCoord = (
					abs(gl_Normal.y) > 0.1
					? worldPos.xz * 2.0
					: vec2((worldPos.x + worldPos.z) * 4.0, worldPos.y + frameTimeCounter)
				);
			}
		#endif
		else if (id == 8) { //shadeless blocks
			normal = vec3(0.0, 1.0, 0.0);
		}
		#if WATER_WAVE_STRENGTH != 0
			else if (id == 12) { //lily pads
				if (worldPos.y <= 31.99 && worldPos.y >= 30.99) {
					worldPos.y -= waterWave(worldPos.xz + 0.5); // + 0.5 to avoid sharp edges in lava displacement when the coords are on the edge of a noisetex pixel
				}
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

	#ifdef GRASS_PATCHES
		if (isGrass) {
			float noise = noiseMap(worldPos.xz) - HUMIDITY_OFFSET;
			if (noise > 0.0) tint.rg += vec2(noise * 0.33333333, noise * -0.125);
			else tint.rb += noise * 0.25;
			tint.g = max(tint.g, tint.r * 0.85);
		}
	#endif

	vPosPlayer = worldPos - actualCameraPosition;
	vPosView = mat3(gbufferModelView) * vPosPlayer;
	gl_Position = gl_ProjectionMatrix * vec4(vPosView, 1.0);

	float glmult = dot(vec4(abs(normal.x), abs(normal.z), max(normal.y, 0.0), max(-normal.y, 0.0)), vec4(0.6, 0.8, 1.0, 0.5));
	glmult = mix(glmult, 1.0, lmcoord.x * lmcoord.x); //increase brightness when block light is high
	tint.rgb *= glmult;
}