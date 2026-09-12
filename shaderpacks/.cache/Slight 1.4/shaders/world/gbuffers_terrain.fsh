#version 330 compatibility

uniform sampler2D lightmap;
uniform sampler2D gtexture;

in float mask;
in float emission;
in vec2 lmcoord;
in vec2 texcoord;
in vec3 normal;
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
	color.rgb += (color.rgb * (emission / 15.0) * emissionMask) * 3.0;

	if (abs(mask - 3.0) < 0.01) {
        color.rgb += color.rgb * 2.0;
    }
}