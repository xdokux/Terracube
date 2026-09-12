#version 130

uniform sampler2D texture;
uniform sampler2D lightmap;
uniform sampler2D depthtex1;

uniform vec4 entityColor;
uniform float blindness;
uniform int isEyeInWater;

varying vec4 color;
varying vec2 coord0;
varying vec2 coord1;

void main()
{
    vec3 light = (1.0 - blindness) * texture2D(lightmap, coord1).rgb;
    vec4 col = color * vec4(light, 1) * texture2D(texture, coord0);
    col.rgb = mix(col.rgb, entityColor.rgb, entityColor.a);

    float fog = (isEyeInWater > 0) ? 1.0 - exp(-gl_FogFragCoord * gl_Fog.density):
    clamp((gl_FogFragCoord - gl_Fog.start) * gl_Fog.scale * 0.5, 0.0, 1.0);

    fog = (isEyeInWater > 2) ? 1.0 - exp(-gl_FogFragCoord * gl_Fog.density):
    clamp((gl_FogFragCoord - gl_Fog.start) * gl_Fog.scale * 0.5, 0.0, 1.0);
	
	if(gl_Fog.color.rgb != vec3(0,0,0))
	{
	   col.rgb = mix(col.rgb, gl_Fog.color.rgb, fog);
	}
	
	/* DRAWBUFFERS:0 */
    gl_FragData[0] = col;
}
