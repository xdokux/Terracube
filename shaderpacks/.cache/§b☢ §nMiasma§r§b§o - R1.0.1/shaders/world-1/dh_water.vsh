#version 130 compatibility

#include "/settings.glsl"

uniform sampler2D lightmap;
uniform float viewWidth, viewHeight;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferModelView;

out vec2 texcoord;
out vec4 color;
out vec3 playerPos;
out vec3 viewSpaceGeoNormal;

#include "/lib/jitter.glsl"

void main() {
    playerPos = (gl_ModelViewMatrix * gl_Vertex).xyz;
    playerPos = (gbufferModelViewInverse * vec4(playerPos,1)).xyz;

    gl_Position = gl_ProjectionMatrix * gbufferModelView * vec4(playerPos,1);
    gl_FogFragCoord = length(playerPos);

	color = gl_Color * texture2D(lightmap, (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy);
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	
	viewSpaceGeoNormal = gl_NormalMatrix * gl_Normal;
	
	gl_Position = ftransform();
	#if TYPE_AA == 1
	gl_Position.xy = TAAJitter(gl_Position.xy, gl_Position.w);
	#endif
}
