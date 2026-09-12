#version 130

out vec4 starData; //rgb = star color, a = flag for weather or not this pixel is a star.

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;

out vec2 TexCoords;
out vec3 Normal;
out vec4 Color;
out vec2 LightmapCoords;

void main() {
    gl_Position = ftransform();
	starData = vec4(gl_Color.rgb, float(gl_Color.r == gl_Color.g && gl_Color.g == gl_Color.b && gl_Color.r > 0.0));
	TexCoords = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	
    LightmapCoords = mat2(gl_TextureMatrix[1]) * gl_MultiTexCoord1.xy;
    LightmapCoords = (LightmapCoords * 33.05f / 32.0f) - (1.05f / 32.0f);
	
	vec3 pos = (gl_ModelViewMatrix * gl_Vertex).xyz;
    pos = (gbufferModelViewInverse * vec4(pos,1)).xyz;
	gl_FogFragCoord = length(pos);
	
    Normal = gl_NormalMatrix * gl_Normal;
    Color = gl_Color;
}
