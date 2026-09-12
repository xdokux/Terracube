#include "/library/bluenoise.glsl"

#define PORTAL_LAYERS 10 // [5 10]
#define PORTAL_SAMPLES 5 // [3 5 10 15 20]

uniform sampler2D colortex0;
uniform sampler2D colortex3;
uniform sampler2D depthtex1;

uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;

uniform float far;
uniform float frameTimeCounter;
uniform float viewWidth;
uniform float viewHeight;

in vec2 texcoord;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

void main() {
    color = texture(colortex0, texcoord);
    float mask = texture(colortex3, texcoord).r;

	vec3 clip = vec3(texcoord * 2.0 - 1.0, texture(depthtex1, texcoord).r * 2.0 - 1.0);
	vec4 view = gbufferProjectionInverse * vec4(clip, 1.0);
	vec3 worldPos = (gbufferModelViewInverse * vec4(view.xyz / view.w, 1.0)).xyz + cameraPosition;

	if (abs(mask - 9.0) < 0.1) {
		vec3 col = vec3(0.01, 0.005, 0.03);

		vec3 rayDir = normalize(worldPos - cameraPosition);
		float portalY = worldPos.y;

		ivec2 screenCoord = ivec2(gl_FragCoord.xy);
		float noise = getNoise(uvec2(screenCoord));

		for (int i = 0; i < PORTAL_LAYERS; i++) {
			float fi = float(i);

			float baseDepth = 0.5 + fi * 1.0;
			float scale = 2.5 - fi * 0.01;

			float layerAngle = fi * 137.5;
			vec2 layerDir = vec2(cos(layerAngle), sin(layerAngle));
			vec2 layerDrift = layerDir * frameTimeCounter * (0.1 + fi * 0.05);

			float safeY = (abs(rayDir.y) < 0.001) ? (rayDir.y >= 0.0 ? 0.001 : -0.001) : rayDir.y;

			bool isUnderneath = cameraPosition.y < portalY;
			float layerGap = 0.35;

			for (int j = 0; j < PORTAL_SAMPLES; j++) {
				float fj = float(j) + (noise - 0.5);
				float subSpacing = layerGap / float(PORTAL_SAMPLES - 1);

				float planeY = isUnderneath ? 
					(portalY + baseDepth + fj * subSpacing) : 
					(portalY - baseDepth - fj * subSpacing);

				float t = (planeY - cameraPosition.y) / safeY;
				vec3 p = cameraPosition + rayDir * t;

				vec2 cellCoord = p.xz * scale + layerDrift;
				vec2 cell = floor(cellCoord);

				float h = fract(sin(dot(cell, vec2(12.9898, 78.233)) + fi * 37.0) * 43758.5453);
				float h2 = fract(sin(dot(cell, vec2(45.32, 19.31)) + fi * 11.0) * 12543.123);
				float h3 = fract(sin(dot(cell, vec2(80.21, 33.98)) + fi * 5.0) * 9812.345);

				vec2 pointOffset = vec2(h2, fract(h2 * 17.0)) - 0.5;

				float density = step(0.75, h);
				float raw = sin(frameTimeCounter * 0.3 + h * 30.0) * 0.5 + 0.5;
				float fade = raw * raw * raw;

				float ch = fract(h * 8.0);
				vec3 c = (ch < 0.5) ? mix(vec3(0.2, 1.0, 0.6), vec3(0.0, 0.7, 1.0), ch * 2.0) : mix(vec3(0.0, 0.7, 1.0), vec3(0.5, 0.2, 0.5), (ch - 0.5) * 2.0);

				float dimming = max(1.0 - fi * 0.15, 0.05);
				float brightBoost = step(0.8, h3) * 50.0 + 1.0;

				vec2 local = cellCoord - cell - 0.5;
				vec2 diff = abs(local - pointOffset * 0.7);
				float edgeSize = 0.2;
				float point = step(max(diff.x, diff.y), edgeSize);

				float subOpacity = exp(-6.0 * (float(j) / float(PORTAL_SAMPLES - 1)));

				col += (c * fade * density * point * h * 2.5 * dimming * brightBoost * subOpacity) / float(PORTAL_SAMPLES) * 2.0;
			}
		}

		color.rgb = col;
	}

	if (abs(mask - 3.0) < 0.1) {
		vec2 uv = worldPos.xz * 0.3 + vec2(frameTimeCounter * 0.7, frameTimeCounter * 0.4);

		float noise = waveNoise(uv);
		float blackNoise = smoothstep(0.0, 1.0, noise);

        float fade = 1.0 - smoothstep(far * 0.9, far, length(worldPos - cameraPosition));
        color.rgb *= 1.0 - blackNoise * 0.3 * fade;
	}

	if (abs(mask - 36.0) < 0.1) {
		vec2 uv = worldPos.xz * 0.1 + vec2(frameTimeCounter * -0.4, frameTimeCounter * 0.6);

		float noise = waveNoise(uv);
		float whiteNoise = smoothstep(0.5, 1.0, noise);

        float fade = 1.0 - smoothstep(far * 0.5, far, length(worldPos - cameraPosition));
        color.rgb += whiteNoise * vec3(0.0, 0.3, 0.5) * fade * smoothstep(0.0, 0.2, color.rgb);
	}
}