#version 330 compatibility

uniform int renderStage;
uniform float viewHeight;
uniform float viewWidth;

in vec4 glcolor;

#include "/world1/lib_world1.glsl"

vec3 screenToView(vec3 screenPos) {
	vec4 ndcPos = vec4(screenPos, 1.0) * 2.0 - 1.0;
	vec4 tmp = gbufferProjectionInverse * ndcPos;
	return tmp.xyz / tmp.w;
}

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

void main() {
	if (renderStage == MC_RENDER_STAGE_STARS) {
		color = glcolor;
	} else {
		// Sky color
		vec3 pos = screenToView(vec3(gl_FragCoord.xy / vec2(viewWidth, viewHeight), 1.0));
		color = vec4(calcSkyColor(normalize(pos)), 1.0);
		color.rgb = vec3(1.0);
		color.rgb = pow(color.rgb, vec3(1.0/2.2));
	}
}
