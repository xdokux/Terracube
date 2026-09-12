#version 120

#define BLUR_ENABLED //Is blur enabled at all?
#define BLUR_QUALITY 10 //Maximum number of sample points to use for blurring. Higher limit = higher performance impact! [5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25]

uniform float pixelSizeX;
uniform sampler2D gaux3; //output from previous stage

varying vec2 texcoord;

float fogify(float x, float width) {
	//fast, vaguely bell curve-shaped function with variable width
	return width / (x * x + width);
}

void main() {
	vec4 color = texture2D(gaux3, texcoord);

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
					newColor = texture2D(gaux3, vec2(x, texcoord.y));
					newWeight = weight * (1.0 - newColor.a) * invBlurRadius1;
					average += vec4(newColor.rgb * newColor.rgb * newWeight, newWeight);
				}

				x = texcoord.x + float(currentStep) * stepSize;
				if (x <= rightBound) {
					newColor = texture2D(gaux3, vec2(x, texcoord.y));
					newWeight = weight * (1.0 - newColor.a) * invBlurRadius1;
					average += vec4(newColor.rgb * newColor.rgb * newWeight, newWeight);
				}
			}
			color.rgb = sqrt(average.rgb / average.a);
		}
	#endif

/* DRAWBUFFERS:3 */
	gl_FragData[0] = color; //gcolor
}