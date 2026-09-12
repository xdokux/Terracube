#version 130

out vec4 starData; //rgb = star color, a = flag for weather or not this pixel is a star.

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;

out vec2 TexCoords;
out vec4 Color;

void main() {
    gl_Position = ftransform();
	starData = vec4(gl_Color.rgb, float(gl_Color.r == gl_Color.g && gl_Color.g == gl_Color.b && gl_Color.r > 0.0));
	TexCoords = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	
	vec3 pos = (gl_ModelViewMatrix * gl_Vertex).xyz;
    pos = (gbufferModelViewInverse * vec4(pos,1)).xyz;
	gl_FogFragCoord = length(pos);
	
    Color = gl_Color;
}
