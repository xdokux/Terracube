uniform sampler2D lightmap;
uniform sampler2D gtexture;

in float mask;
in float emission;
in vec2 lmcoord;
in vec2 texcoord;
in vec3 normal;
in vec3 localPos;
in vec4 glcolor;

/* RENDERTARGETS: 0,1,2,3 */
layout(location = 0) out vec4 color;
layout(location = 1) out vec4 packLight;
layout(location = 2) out vec4 packNormal;
layout(location = 3) out vec4 packMask;

void main() {
	color = texture(gtexture, texcoord) * glcolor;
	if (color.a < 0.1) discard;
	
	packLight = vec4(lmcoord, 0.0, 1.0);
	packNormal = vec4(normal * 0.5 + 0.5, 1.0);
	packMask = vec4(mask, 0.0, 0.0, 1.0);

	float luminance = dot(color.rgb, vec3(0.2126, 0.7152, 0.0722));
    float emissionMask = smoothstep(0.4, 1.0, luminance);

	vec3 emissionStrength = vec3(5.0);
	if (abs(mask - 26.0) < 0.1) emissionMask = smoothstep(0.7, 1.5, luminance);
	if (abs(mask - 32.0) < 0.1 || abs(mask - 33.0) < 0.1 || abs(mask - 34.0) < 0.1)
	emissionMask = exp(-dot(fract(localPos) - vec3(0.5), fract(localPos) - vec3(0.5)) * 15.0);

	if (abs(mask - 35.0) < 0.1) emissionMask = smoothstep(0.5, 1.0, luminance);

	if (abs(mask - 23.0) < 0.1) emissionMask = smoothstep(0.3, 1.0, luminance);

	if (abs(mask - 21.0) < 0.1 || abs(mask - 22.0) < 0.1) emissionMask = smoothstep(0.3, 1.0, fract(localPos.y));
	if (abs(mask - 30.0) < 0.1 || abs(mask - 31.0) < 0.1) emissionMask = smoothstep(0.5, 1.0, fract(localPos.y));
	if (abs(mask - 21.0) < 0.1 || abs(mask - 26.0) < 0.1) emissionStrength = vec3(2.0, 1.0, 0.5) * 20.0;
	if (abs(mask - 22.0) < 0.1) emissionStrength = vec3(0.5, 1.5, 2.0) * 40.0;
	if (abs(mask - 30.0) < 0.1) emissionStrength = vec3(2.0, 1.0, 0.5) * 20.0;
	if (abs(mask - 31.0) < 0.1) emissionStrength = vec3(0.5, 1.5, 2.0) * 40.0;

	if (abs(mask - 32.0) < 0.1) emissionStrength = vec3(2.0, 1.0, 0.5) * 10.0;
	if (abs(mask - 33.0) < 0.1) emissionStrength = vec3(0.5, 1.0, 2.0) * 15.0;
	if (abs(mask - 34.0) < 0.1) emissionStrength = vec3(1.5, 1.0, 0.0) * 15.0;

	if (abs(mask - 23.0) < 0.1) emissionStrength = vec3(2.0, 1.0, 0.5) * 7.0;
	if (abs(mask - 24.0) < 0.1 || abs(mask - 35.0) < 0.1) emissionStrength = vec3(0.5, 1.5, 2.0) * 15.0;

	color.rgb += (color.rgb * (emission / 15.0) * emissionMask) * emissionStrength;

	if (abs(mask - 3.0) < 0.1) color.rgb += color.rgb * vec3(3.0, 1.0, 1.0) * 2.0;
	if (abs(mask - 4.0) < 0.1) color.rgb += color.rgb * vec3(1.0, 0.5, 0.0);
	if (abs(mask - 16.0) < 0.1) color.rgb *= 0.7;
	if (abs(mask - 17.0) < 0.1) color.rgb = color.rgb * vec3(2.0, 1.5, 1.0);
	if (abs(mask - 18.0) < 0.1) color.rgb += color.rgb * vec3(0.0, 1.0, 2.5);
}