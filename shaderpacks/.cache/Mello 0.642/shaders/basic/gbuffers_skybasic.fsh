#include "/library/time.glsl"
#include "/library/sky.glsl"

uniform float viewHeight;
uniform float viewWidth;

uniform mat4 gbufferProjection;

uniform int renderStage;

in vec4 glcolor;

layout(location = 0) out vec4 color;

void main() {
	if (renderStage == MC_RENDER_STAGE_STARS) {
		color = glcolor * 1.5;
		return;
	}

	calculateTimeBlend();

	vec2 screenUV = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
	vec4 ndcPos = vec4(screenUV, 1.0, 1.0) * 2.0 - 1.0;
	vec4 tmp = gbufferProjectionInverse * ndcPos;
	vec3 viewDir = normalize(tmp.xyz / tmp.w);

	vec3 skyColor = calculateSkyGradient(viewDir);
	vec3 skyMie = calculateMie(viewDir);
	vec3 sky = skyColor + skyMie;
	
	color = vec4(sky, 0.0);
}