layout(location = 0) out vec4 fragData0;
layout(location = 1) out vec4 fragData1;
/*
Sildur's Basic Shaders:
https://www.patreon.com/Sildur
https://sildurs-shaders.github.io/
https://twitter.com/SildurFX

Permissions:
You are not allowed to edit, copy code or share my shaderpack under a different name or claim it as yours.
*/

#define gbuffers_textured
#include "shaders.settings"


// vertex

//Moving entities IDs
//See block.properties for mapped ids
#define ENTITY_SMALLGRASS   10031.0	//
#define ENTITY_LOWERGRASS   10175.0	//lower half only in 1.13+
#define ENTITY_UPPERGRASS	10176.0 //upper half only used in 1.13+
#define ENTITY_SMALLENTS    10059.0	//sapplings(6), dandelion(37), rose(38), carrots(141), potatoes(142), beetroot(207)

#define ENTITY_LEAVES       10018.0	//161 new leaves
#define ENTITY_VINES        10106.0

#define ENTITY_WATER		10008.0	//9
#define ENTITY_LILYPAD      10111.0	//
#define ENTITY_ICE			10079.0	//transparent reflections, stained glass(95, 160), slimeblock(165)

#define ENTITY_FIRE         10051.0	//
#define ENTITY_LAVA   		10010.0	//11
#define ENTITY_EMISSIVE		10089.0 //emissive blocks defined in block.properties
#define ENITIY_SOULFIRE		10091.0
#define ENTITY_WAVING_LANTERN 10090.0
#define ENTITY_INVERTED_LOWER 10177.0	//hanging_roots
#define ENTITY_NON_DIFFUSE 20000.0


// fragment

#ifdef Reflections
mat2 rmatrix(float rad){
	return mat2(vec2(cos(rad), -sin(rad)), vec2(sin(rad), cos(rad)));
}

float calcWaves(vec2 coord, float water){
	vec2 movement = abs(vec2(0.0, -frameTimeCounter * 0.31365*water));
		 
	coord *= 0.262144;
	vec2 coord0 = coord * rmatrix(1.0) - movement * 4.0;
		 coord0.y *= 3.0;
	vec2 coord1 = coord * rmatrix(0.5) - movement * 1.5;
		 coord1.y *= 3.0;		 
	vec2 coord2 = coord + movement * 0.5;
		 coord2.y *= 3.0;
	
	float wave = 1.0 - texture2D(noisetex,coord0 * 0.005).x * 10.0;		//big waves
		  wave += texture2D(noisetex,coord1 * 0.010416).x * 7.0;		//small waves
		  wave += sqrt(texture2D(noisetex,coord2 * 0.045).x * 6.5) * 1.33;//noise texture
		  wave *= 0.0157;
	
	return wave;
}

vec3 calcBump(vec2 coord, float water){
	const vec2 deltaPos = vec2(0.25, 0.0);

	float h0 = calcWaves(coord, water);
	float h1 = calcWaves(coord + deltaPos.xy, water);
	float h2 = calcWaves(coord - deltaPos.xy, water);
	float h3 = calcWaves(coord + deltaPos.yx, water);
	float h4 = calcWaves(coord - deltaPos.yx, water);

	float xDelta = ((h1-h0)+(h0-h2));
	float yDelta = ((h3-h0)+(h0-h4));

	return vec3(vec2(xDelta,yDelta)*0.45, 0.55); //z = 1.0-0.5
}
#endif

vec3 toScreenSpace(vec3 pos) {
	vec4 iProjDiag = vec4(vxProjInv[0].x, vxProjInv[1].y, vxProjInv[2].zw);
    vec3 p3 = pos * 2.0 - 1.0;
    vec4 viewPos = iProjDiag * p3.xyzz + vxProjInv[3];
    return viewPos.xyz / viewPos.w;
}

vec4 encode (vec3 n, float material){
    return vec4(n.xy*inversesqrt(n.z*8.0+8.0) + 0.5, material/2.0, 1.0);
}


void voxy_emitFragment(VoxyFragmentParameters parameters) {

    //vertex

    float mat = 0.0;
    #ifdef Reflections
    #ifdef WaterReflection
	    if(parameters.customId == ENTITY_WATER)mat = 1.0;
    #endif
    #ifdef TransparentReflections
	    if(parameters.customId == ENTITY_ICE)mat = 2.0; //various ids are mapped to ice in block.properties
    #endif
    #endif


    //fragment

    #ifndef customLight
        vec4 tex = parameters.sampledColour * texture2D(lightmap, parameters.lightMap) * parameters.tinting;
    #else
        //Mix default MC skylight with custom emissive light
        vec4 tex = parameters.sampledColour * parameters.tinting;
	    float torchmap = clamp(parameters.lightMap.x-0.5/16.0, 0.0, 1.0); //must be clamped to fix enchanted items
	    tex.rgb *= mix(texture2D(lightmap, vec2(0.5 / 16.0, parameters.lightMap.y)).rgb, vec3(emissive_R,emissive_G,emissive_B)*torchmap, torchmap);
    #endif

    #ifdef Colorboost
	    tex.rgb = pow(tex.rgb*1.20, vec3(1.20));
    #endif
		
        vec3 fragPos = toScreenSpace(vec3(gl_FragCoord.xy / vec2(viewWidth, viewHeight), gl_FragCoord.z));
		vec3 normal = vec3(0.0);

		switch (uint(parameters.face) >> 1u) {
			case 0u:
			normal.xyz = vxModelView[1].xyz;
			break;
			case 1u:
			normal.xyz  = vxModelView[2].xyz;
			break;
			case 2u:
			normal.xyz  = vxModelView[0].xyz;
			break;
		}
		if ((parameters.face & 1) == 0) {
			normal.xyz  = -normal.xyz ;
		}

    //Lighting
    float NdotLight = clamp(dot(normal, normalize(shadowLightPosition))*1.02-0.02,0.0,1.0);	
    if (parameters.customId == ENTITY_SMALLGRASS
    || parameters.customId == ENTITY_LOWERGRASS
    || parameters.customId == ENTITY_UPPERGRASS
    || parameters.customId == ENTITY_SMALLENTS
    || parameters.customId == ENTITY_LEAVES
    || parameters.customId == ENTITY_VINES
    || parameters.customId == ENTITY_LILYPAD
    || parameters.customId == ENTITY_FIRE
    || parameters.customId == ENTITY_WAVING_LANTERN	
    || parameters.customId == ENTITY_EMISSIVE	
    || parameters.customId == ENTITY_NON_DIFFUSE) {
    NdotLight = 0.60;
    }
	NdotLight *= (1.0-rainStrength);
	tex.rgb *= clamp((1.0 + NdotLight) * 0.65,  0.0, 1.0);

	if(mat < 0.9) normal *= 0.0; //don't need none reflective normals in buffer

	#ifdef Fog
		float newFar = max(far, float(vxRenderDistance * 16.0));
		tex.rgb = mix(tex.rgb, fogColor, clamp(max((length(fragPos) - fogStart) / max(fogEnd - fogStart, 0.0001), length(fragPos) / newFar * 12.5 - 11.5), 0.0, 1.0));
	#endif

    fragData0 = tex;
    fragData1 = encode(normal, mat);
}