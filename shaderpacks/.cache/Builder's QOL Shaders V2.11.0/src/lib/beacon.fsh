#ifdef FANCY_BEACONS
	if (!gl_FrontFacing) discard; //ignore back faces

	//setup some position variables
	vec2 playerNorm2 = normalize(vPosPlayer.xz);
	vec3 playerNorm3 = normalize(vPosPlayer);
	vec3 cylinderProjection = playerNorm3 * (playerNorm2.x / playerNorm3.x);

	vec3 farTest = dot(playerNorm2, beaconPosPlayer) * cylinderProjection; //closest point to the beaconPosPlayer which is along our view vector
	if (square(calcBeaconWidth(farTest.y + actualCameraPosition.y)) < distanceSq2(beaconPosPlayer, farTest.xz)) discard; //if this closest point is still not inside the beam, then it's unlikely that our view vector intersects with the beam at all.
	vec3 nearTest = (length(beaconPosPlayer) - 0.328125) * cylinderProjection; //furthest possible point from beaconPosPlayer that calcBeaconWidth can output
	vec3 midTest = (nearTest + farTest) * 0.5;

	//binary split search to test for intersections.
	//increasing the number of steps in this loop will increase the precision of the results we get.
	for (int i = 0; i < 8; i++) {
		if (square(calcBeaconWidth(midTest.y + actualCameraPosition.y)) < distanceSq2(beaconPosPlayer, midTest.xz)) nearTest = midTest;
		else farTest = midTest;
		midTest = (nearTest + farTest) * 0.5;
	}

	vec2 tc = vec2(atan(midTest.z - beaconPosPlayer.y, midTest.x - beaconPosPlayer.x) * 0.636619772 /* 2 / pi */, midTest.y + actualCameraPosition.y);
	vec4 color = texture2D(texture, tc + vec2(frameTimeCounter, frameTimeCounter * -4.0)) * tint;

	tc.y *= 3.0;
	float noise = -0.3125;
	noise += random(tc * 0.5 + goldenOffset0 * frameTimeCounter * 2.0  /* 2/1 */,  2.0) * 0.4;     //0.4^1
	noise += random(tc       + goldenOffset1 * frameTimeCounter        /* 2/2 */,  4.0) * 0.16;    //0.4^2
	noise += random(tc * 2.0 + goldenOffset2 * frameTimeCounter * 0.66 /* 2/3 */,  8.0) * 0.064;   //0.4^3
	noise += random(tc * 4.0 + goldenOffset3 * frameTimeCounter * 0.25 /* 2/4 */, 16.0) * 0.0256;  //0.4^4
	noise += random(tc * 8.0 + goldenOffset4 * frameTimeCounter * 0.4  /* 2/5 */, 32.0) * 0.01024; //0.4^5
	noise = abs(noise);
	if (noise < 0.125) color.rgb = mix(color.rgb, tint.rgb * (2.0 - tint.rgb), square(1.0 - noise * 8.0));

	//adjust fragDepth to match that of our midTest.
	vec4 fragPos = gbufferProjection * vec4(mat3(gbufferModelView) * midTest, 1.0);
	gl_FragDepth = fragPos.z / fragPos.w * 0.5 + 0.5;
#else
	vec4 color = texture2D(texture, texcoord) * tint;
#endif