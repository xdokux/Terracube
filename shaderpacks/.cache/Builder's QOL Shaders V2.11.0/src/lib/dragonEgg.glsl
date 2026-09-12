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