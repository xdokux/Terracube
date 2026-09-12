#ifdef FANCY_BEACONS
	vec3 vPosView = (gl_ModelViewMatrix * gl_Vertex).xyz;
	vPosPlayer = mat3(gbufferModelViewInverse) * vPosView;
	beaconPosPlayer = floor(vPosPlayer.xz + actualCameraPosition.xz) + 0.5 - actualCameraPosition.xz;
	vec2 playerPosRelativeToBeacon = vPosPlayer.xz - beaconPosPlayer;

	if (lengthSquared2(playerPosRelativeToBeacon) > 0.0625) { //transparent layer. testing position instead of gl_Color.a because gl_Color.a is the same on both layers in 1.7
		gl_Position = vec4(100.0);
		return;
	}

	vPosPlayer.xz += playerPosRelativeToBeacon * 1.5; //make the beam a little bit wider, so that we have more fragments to work with.
	vPosView = mat3(gbufferModelView) * vPosPlayer;
	gl_Position = gl_ProjectionMatrix * vec4(vPosView, 1.0);
#else
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	gl_Position = ftransform();
#endif

tint = gl_Color;