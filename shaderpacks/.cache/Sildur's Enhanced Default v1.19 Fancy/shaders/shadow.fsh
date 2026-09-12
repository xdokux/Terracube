#version 120
/* DRAWBUFFERS:02 */ //0=gcolor, 2=gnormal for normals
/*
Sildur's Enhanced Default:
https://www.patreon.com/Sildur
https://sildurs-shaders.github.io/
https://twitter.com/SildurFX
https://www.curseforge.com/minecraft/customization/sildurs-enhanced-default

Permissions:
You are not allowed to edit, copy code or share my shaderpack under a different name or claim it as yours.
*/

varying vec3 texcoord;
uniform sampler2D texture;
uniform int blockEntityId;

void main() {

	vec4 color = texture2D(texture, texcoord.xy)*texcoord.z;
	if(blockEntityId == 10089.0)color *= 0.0;			 	//remove beacon beam shadows, 10089 is actually the id of all emissive blocks but only the beam should be a block entity

	gl_FragData[0] = color;
	gl_FragData[1] = vec4(0.0); //improves performance	
}