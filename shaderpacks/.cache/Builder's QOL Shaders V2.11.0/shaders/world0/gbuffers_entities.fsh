#version 120

uniform int entityId;
uniform sampler2D texture;
uniform vec4 entityColor;

varying vec2 lmcoord;
varying vec2 texcoord;
varying vec4 tint;

void main() {
	vec4 color;
	float lightAlpha;
	if (entityId == 10000) {
		color = tint;
		lightAlpha = 1.0;
	}
	else {
		color = texture2D(texture, texcoord) * tint;
		if (color.a < 0.01) discard; //fix phantoms, and maybe other entities too.
		color.rgb = mix(color.rgb, entityColor.rgb, entityColor.a);
		lightAlpha = step(0.75, color.a);
	}

/* DRAWBUFFERS:04 */
	gl_FragData[0] = color; //gcolor
	gl_FragData[1] = vec4(lmcoord, 1.0, lightAlpha); //gaux1
}