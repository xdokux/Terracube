#version 120
/*
Sildur's Enhanced Default:
https://www.patreon.com/Sildur
https://sildurs-shaders.github.io/
https://twitter.com/SildurFX
https://www.curseforge.com/minecraft/customization/sildurs-enhanced-default

Permissions:
You are not allowed to edit, copy code or share my shaderpack under a different name or claim it as yours.
*/

varying vec2 texcoord;
varying vec4 color;

void main() {
	
	gl_Position = ftransform();
	
	texcoord = (gl_MultiTexCoord0).xy;

	color = gl_Color;
}
