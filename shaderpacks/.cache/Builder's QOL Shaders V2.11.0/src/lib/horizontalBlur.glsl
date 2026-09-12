vec4 color = texture2D(blurInputSampler, texcoord);

#ifdef BLUR_ENABLED
	float blurRadius = 1.0 - color.a;
	if (blurRadius > 0.0) {
		float invBlurRadius1 = 1.0 / blurRadius;
		blurRadius *= 256.0; //actual radius in pixels
		float invBlurRadius2 = 1.0 / blurRadius;

		vec4 average = vec4(color.rgb * color.rgb, 1.0);

		int stepCount = int(clamp(blurRadius, 1.0, float(BLUR_QUALITY)));
		float invStepCount = 1.0 / float(stepCount);
		float stepSize = blurRadius * pixelSizeX * invStepCount;
		float leftBound = pixelSizeX * 0.5;
		float rightBound = 1.0 - leftBound;

		for (int currentStep = 1; currentStep <= stepCount; currentStep++) {
			float weight = fogify(currentStep * invStepCount, 0.35);
			float x;
			vec4 newColor;
			float newWeight;

			x = texcoord.x - float(currentStep) * stepSize;
			if (x >= leftBound) {
				newColor = texture2D(blurInputSampler, vec2(x, texcoord.y));
				newWeight = weight * (1.0 - newColor.a) * invBlurRadius1;
				average += vec4(newColor.rgb * newColor.rgb * newWeight, newWeight);
			}

			x = texcoord.x + float(currentStep) * stepSize;
			if (x <= rightBound) {
				newColor = texture2D(blurInputSampler, vec2(x, texcoord.y));
				newWeight = weight * (1.0 - newColor.a) * invBlurRadius1;
				average += vec4(newColor.rgb * newColor.rgb * newWeight, newWeight);
			}
		}
		color.rgb = sqrt(average.rgb / average.a);
	}
#endif