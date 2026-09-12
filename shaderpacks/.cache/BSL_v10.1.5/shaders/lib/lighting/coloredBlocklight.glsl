vec3 ApplyHandlightColor(vec3 mcblCol, vec3 worldPos) {
    vec3 heldLightPos = worldPos + relativeEyePosition + vec3(0.0, 0.5, 0.0);

    float falloff = max(1.0 - 2.0 / 15.0 * length(heldLightPos), 0.0);
	falloff = pow(0.3, length(heldLightPos)) * 0.5;

	int heldData = heldItemId % 100;
	int heldData2 = heldItemId2 % 100;

	vec3 handlightColor = vec3(0.0);
	if (heldData >= 1 && heldData <= 50) {
		handlightColor += lightColorsRGB[heldData - 1];
	}
	if (heldData2 >= 1 && heldData2 <= 50) {
		handlightColor += lightColorsRGB[heldData2 - 1];
	}

	mcblCol = mix(mcblCol, handlightColor, falloff);

    return mcblCol;
}

#ifdef MCBL_SS
vec2 Reprojection(vec3 pos) {
	pos = pos * 2.0 - 1.0;

	vec4 viewPosPrev = gbufferProjectionInverse * vec4(pos, 1.0);
	viewPosPrev /= viewPosPrev.w;
	viewPosPrev = gbufferModelViewInverse * viewPosPrev;

	vec3 cameraOffset = cameraPosition - previousCameraPosition;
	cameraOffset *= float(pos.z > 0.56);

	vec4 previousPosition = viewPosPrev + vec4(cameraOffset, 0.0);
	previousPosition = gbufferPreviousModelView * previousPosition;
	previousPosition = gbufferPreviousProjection * previousPosition;
	return previousPosition.xy / previousPosition.w * 0.5 + 0.5;
}
#endif

float GetMCBLLegacyMask(vec3 worldPos) {
	#if MCBL_SS_MODE == 0 && defined MULTICOLORED_BLOCKLIGHT
	vec3 maskPos = abs(worldPos / (voxelMapSize / 2));
	return float(maskPos.x > 0.9 || maskPos.y > 0.9 || maskPos.z > 0.9);
	#else
	return 1.0;
	#endif
}

vec3 SampleLightTex(sampler3D lighttex, vec3 voxelMapPos) {
	// Workaround for colored blocklight flickering bug. Starting from 1.21.11 (or possibly earlier), campfire block
	// causes the light texture to flicker between point and linear filtering. (iris bug?)
	voxelMapPos -= 0.5;

	ivec3 flr = ivec3(floor(voxelMapPos));
	vec3 frc = fract(voxelMapPos);

	vec3 light000 = texelFetch(lighttex, flr + ivec3(0, 0, 0), 0).rgb;
	vec3 light001 = texelFetch(lighttex, flr + ivec3(0, 0, 1), 0).rgb;
	vec3 light010 = texelFetch(lighttex, flr + ivec3(0, 1, 0), 0).rgb;
	vec3 light011 = texelFetch(lighttex, flr + ivec3(0, 1, 1), 0).rgb;
	vec3 light100 = texelFetch(lighttex, flr + ivec3(1, 0, 0), 0).rgb;
	vec3 light101 = texelFetch(lighttex, flr + ivec3(1, 0, 1), 0).rgb;
	vec3 light110 = texelFetch(lighttex, flr + ivec3(1, 1, 0), 0).rgb;
	vec3 light111 = texelFetch(lighttex, flr + ivec3(1, 1, 1), 0).rgb;

	vec3 light00 = mix(light000, light001, frc.z);
	vec3 light01 = mix(light010, light011, frc.z);
	vec3 light10 = mix(light100, light101, frc.z);
	vec3 light11 = mix(light110, light111, frc.z);

	vec3 light0 = mix(light00, light01, frc.y);
	vec3 light1 = mix(light10, light11, frc.y);

	vec3 light = mix(light0, light1, frc.x);

	return light;
}

vec3 ApplyMultiColoredBlocklight(vec3 blocklightCol, vec3 screenPos, vec3 worldPos, vec3 normal, float hand) {
	vec3 mcblCol = vec3(0.0);
	float voxelBounds = 0.0;

	#if defined MULTICOLORED_BLOCKLIGHT
	vec3 worldNormal = mat3(gbufferModelViewInverse) * normal;
	worldPos += worldNormal * 0.5;

	#ifdef WORLD_CURVATURE
	worldPos.y += dot(worldPos.xz, worldPos.xz) / WORLD_CURVATURE_SIZE;
	#endif

	vec3 voxelMapPos = WorldToVoxel(worldPos);
	
	if (IsInVoxelMapVolume(voxelMapPos)) {
		voxelBounds = GetVoxelMapSoftBounds(voxelMapPos);
		
		int iFrameMod2 = int(frameCounter % 2);
		
		if (iFrameMod2 == 0) {
			mcblCol = SampleLightTex(lighttex0, voxelMapPos);
		} else {
			mcblCol = SampleLightTex(lighttex1, voxelMapPos);
		}

		mcblCol = ApplyHandlightColor(mcblCol, worldPos);

		mcblCol = normalize(mcblCol + vec3(1e-5));
		mcblCol *= mcblCol;
		mcblCol *= BLOCKLIGHT_I * BLOCKLIGHT_I * 2.0;
		
		blocklightCol = mix(blocklightCol, mcblCol, voxelBounds);
	}
	#endif

	#ifdef MCBL_SS
	if (hand < 0.5) {
		screenPos.xy = Reprojection(screenPos);
	}

	vec3 ssmcblCol = texture2DLod(colortex9, screenPos.xy, 2).rgb;
	float ssmcblFactor = min((ssmcblCol.r + ssmcblCol.g + ssmcblCol.b) * 2048.0, 1.0);

	#if MCBL_SS_MODE == 0 && defined MULTICOLORED_BLOCKLIGHT
	ssmcblFactor *= 1.0 - voxelBounds;
	#endif
	
	ssmcblCol = ssmcblCol + 0.000001;
	ssmcblCol = normalize(ssmcblCol * ssmcblCol) * 0.875 + 0.125;
	ssmcblCol *= BLOCKLIGHT_I * BLOCKLIGHT_I * 1.25;

	blocklightCol = mix(blocklightCol, ssmcblCol, ssmcblFactor);
	#endif

	return blocklightCol;
}