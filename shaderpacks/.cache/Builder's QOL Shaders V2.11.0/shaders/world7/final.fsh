#version 120

#define BLUR_ENABLED //Is blur enabled at all?
#define BLUR_QUALITY 10 //Maximum number of sample points to use for blurring. Higher limit = higher performance impact! [5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25]

uniform float pixelSizeY;
uniform sampler2D composite; //output from previous stage

varying vec2 texcoord;

float fogify(float x, float width) {
	//fast, vaguely bell curve-shaped function with variable width
	return width / (x * x + width);
}

void main() {
	vec4 color = texture2D(composite, texcoord);

	#ifdef BLUR_ENABLED
		float blurRadius = 1.0 - color.a;
		if (blurRadius > 0.0) {
			float invBlurRadius1 = 1.0 / blurRadius;
			blurRadius *= 256.0; //actual radius in pixels
			float invBlurRadius2 = 1.0 / blurRadius;

			vec4 average = vec4(color.rgb * color.rgb, 1.0);

			int stepCount = int(clamp(blurRadius, 1.0, float(BLUR_QUALITY)));
			float invStepCount = 1.0 / float(stepCount);
			float stepSize = blurRadius * pixelSizeY * invStepCount;
			float bottomBound = pixelSizeY * 0.5;
			float topBound = 1.0 - bottomBound;

			for (int currentStep = 1; currentStep <= stepCount; currentStep++) {
				float weight = fogify(currentStep * invStepCount, 0.35);
				float y;
				vec4 newColor;
				float newWeight;

				y = texcoord.y - float(currentStep) * stepSize;
				if (y >= bottomBound) {
					newColor = texture2D(composite, vec2(texcoord.x, y));
					newWeight = weight * (1.0 - newColor.a) * invBlurRadius1;
					average += vec4(newColor.rgb * newColor.rgb * newWeight, newWeight);
				}

				y = texcoord.y + float(currentStep) * stepSize;
				if (y <= topBound) {
					newColor = texture2D(composite, vec2(texcoord.x, y));
					newWeight = weight * (1.0 - newColor.a) * invBlurRadius1;
					average += vec4(newColor.rgb * newColor.rgb * newWeight, newWeight);
				}
			}
			color.rgb = sqrt(average.rgb / average.a);
		}
	#endif

	gl_FragColor = color; //screen output
}