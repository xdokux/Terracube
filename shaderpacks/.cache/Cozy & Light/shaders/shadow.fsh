#version 460 compatibility

uniform sampler2D lightmap;
uniform sampler2D texture;

const float sunPathRotation = -40.0f;

varying vec2 lmcoord;
varying vec2 texcoord;
varying vec4 glcolor;

void main() {
	vec4 color = texture2D(texture, texcoord) * glcolor;

	gl_FragData[0] = color;
}