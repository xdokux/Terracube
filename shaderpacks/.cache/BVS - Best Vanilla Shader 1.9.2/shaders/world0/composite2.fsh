#version 130

//Shader by LoLip_p

#include "/settings.glsl"

in vec2 TexCoords;

uniform sampler2D colortex0;
uniform float viewWidth, viewHeight;

#if DOF == 1
uniform sampler2D depthtex1;

uniform float aspectRatio;
uniform float centerDepthSmooth;
uniform mat4 gbufferProjection;

vec2 dofOffsets[60] = vec2[60](
	vec2( 0.0    ,  0.25  ),
	vec2(-0.2165 ,  0.125 ),
	vec2(-0.2165 , -0.125 ),
	vec2( 0      , -0.25  ),
	vec2( 0.2165 , -0.125 ),
	vec2( 0.2165 ,  0.125 ),
	vec2( 0      ,  0.5   ),
	vec2(-0.25   ,  0.433 ),
	vec2(-0.433  ,  0.25  ),
	vec2(-0.5    ,  0     ),
	vec2(-0.433  , -0.25  ),
	vec2(-0.25   , -0.433 ),
	vec2( 0      , -0.5   ),
	vec2( 0.25   , -0.433 ),
	vec2( 0.433  , -0.2   ),
	vec2( 0.5    ,  0     ),
	vec2( 0.433  ,  0.25  ),
	vec2( 0.25   ,  0.433 ),
	vec2( 0      ,  0.75  ),
	vec2(-0.2565 ,  0.7048),
	vec2(-0.4821 ,  0.5745),
	vec2(-0.51295,  0.375 ),
	vec2(-0.7386 ,  0.1302),
	vec2(-0.7386 , -0.1302),
	vec2(-0.51295, -0.375 ),
	vec2(-0.4821 , -0.5745),
	vec2(-0.2565 , -0.7048),
	vec2(-0      , -0.75  ),
	vec2( 0.2565 , -0.7048),
	vec2( 0.4821 , -0.5745),
	vec2( 0.51295, -0.375 ),
	vec2( 0.7386 , -0.1302),
	vec2( 0.7386 ,  0.1302),
	vec2( 0.51295,  0.375 ),
	vec2( 0.4821 ,  0.5745),
	vec2( 0.2565 ,  0.7048),
	vec2( 0      ,  1     ),
	vec2(-0.2588 ,  0.9659),
	vec2(-0.5    ,  0.866 ),
	vec2(-0.7071 ,  0.7071),
	vec2(-0.866  ,  0.5   ),
	vec2(-0.9659 ,  0.2588),
	vec2(-1      ,  0     ),
	vec2(-0.9659 , -0.2588),
	vec2(-0.866  , -0.5   ),
	vec2(-0.7071 , -0.7071),
	vec2(-0.5    , -0.866 ),
	vec2(-0.2588 , -0.9659),
	vec2(-0      , -1     ),
	vec2( 0.2588 , -0.9659),
	vec2( 0.5    , -0.866 ),
	vec2( 0.7071 , -0.7071),
	vec2( 0.866  , -0.5   ),
	vec2( 0.9659 , -0.2588),
	vec2( 1      ,  0     ),
	vec2( 0.9659 ,  0.2588),
	vec2( 0.866  ,  0.5   ),
	vec2( 0.7071 ,  0.7071),
	vec2( 0.5    ,  0.8660),
	vec2( 0.2588 ,  0.9659)
);

vec3 DepthOfField(vec3 color, float z) {
	vec3 dof = vec3(0.0);
	float hand = float(z < 0.56);
	
	float fovScale = gbufferProjection[1][1] / 1.37;
	float coc = max(abs(z - centerDepthSmooth) * DOF_STRENGTH - 0.01, 0.0);
	coc = coc / sqrt(coc * coc + 0.1);
	
	if (coc > 0.0 && hand < 0.5) {
		for(int i = 0; i < 60; i++) {
			vec2 offset = dofOffsets[i] * coc * 0.015 * fovScale * vec2(1.0 / aspectRatio, 1.0);
			float lod = log2(viewHeight * aspectRatio * coc * fovScale / 320.0);
			dof += texture2DLod(colortex0, TexCoords + offset, lod).rgb;
		}
		dof /= 60.0;
	}
	else dof = color;
	return dof;
}
#endif

#if AUTO_EXPOSURE == 1
uniform int worldTime;
uniform sampler2D colortex5;

const bool colortex5Clear = false;
const bool colortex0MipmapEnabled = true;

float pw = 1.0 / viewWidth;
float ph = 1.0 / viewHeight;

void AutoExposure(inout vec3 color, inout float exposure, float tempExposure) {
	float exposureLod = log2(viewHeight * AUTO_EXPOSURE_RADIUS);
	
	exposure = length(texture2DLod(colortex0, vec2(0.5), exposureLod).rgb);
	exposure = max(exposure, 0.0001);
	
	color /= tempExposure + 0.125;
}

void Tonemap(inout vec3 color) {
	color *= exp2(1.75 + EXPOSURE);

	color = color / vec3(TONEMAP_WHITE), vec3(1.0 / TONEMAP_WHITE);

	color = clamp(color, vec3(0.0), vec3(1.0));
}
#else
const bool colortex5Clear = true;
const bool colortex0MipmapEnabled = false;
#endif

void main() {
	vec3 color = texture2D(colortex0, TexCoords).rgb;
	
	#if DOF == 1
	float z = texture2D(depthtex1, TexCoords).r;
	color = DepthOfField(color, z);
    #endif
	
	#if AUTO_EXPOSURE == 1
	float temporalData = 0.0;
	float tempExposure = texture2D(colortex5, vec2(pw, ph)).r;
	
	float exposure = 1.0;
	AutoExposure(color, exposure, tempExposure);
	
	Tonemap(color);
	
	if (TexCoords.x < 2.0 * pw && TexCoords.y < 2.0 * ph)
		temporalData = mix(tempExposure, sqrt(exposure), AUTO_EXPOSURE_SPEED);
		
	/* DRAWBUFFERS:05 */
	gl_FragData[0].rgb = color;
	gl_FragData[1].r = temporalData;
	#else
	gl_FragData[0].rgb = color;
	#endif
}
