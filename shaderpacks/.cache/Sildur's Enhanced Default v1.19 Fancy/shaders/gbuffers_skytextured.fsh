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

#define gbuffers_skytextured
#include "shaders.settings"

varying vec2 texcoord;
varying vec4 color;
uniform sampler2D texture;

#ifdef IRIS_END_FIX
    #if defined(IS_IRIS) && (MC_VERSION >= 12105)
        uniform int biome_category;
    #endif
#endif

void main() {

    vec4 albedo = texture2D(texture, texcoord.xy)*color;
#ifdef IRIS_END_FIX
    #if defined(IS_IRIS) && (MC_VERSION >= 12105)
        if(biome_category == CAT_THE_END) albedo.rgb *= 0.2;
    #endif
#endif
	gl_FragData[0] = albedo;
    gl_FragData[1] = vec4(0.0); //fills normal buffer with 0.0, improves overall performance
}
