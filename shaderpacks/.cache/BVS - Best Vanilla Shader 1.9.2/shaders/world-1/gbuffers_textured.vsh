#version 130

in vec3 mc_Entity;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;

out vec4 color;
out vec2 coord0;
out vec2 coord1;

void main()
{
    vec3 pos = (gl_ModelViewMatrix * gl_Vertex).xyz;
    pos = (gbufferModelViewInverse * vec4(pos,1)).xyz;

    gl_Position = gl_ProjectionMatrix * gbufferModelView * vec4(pos,1);
    gl_FogFragCoord = length(pos);

    vec3 normal = gl_NormalMatrix * gl_Normal;
    normal = (mc_Entity.x == 1.0) ? vec3(0, 1, 0) : (gbufferModelViewInverse * vec4(normal,0)).xyz;
	
    float light = 1.5;
	if (int(mc_Entity.x + 0.5) != 1001) {
		light = min(normal.x * normal.x * 0.6f + normal.y * normal.y * 0.25f * (3.0f + normal.y) + normal.z * normal.z * 0.8f, 1.0f);
    }

    color = vec4(gl_Color.rgb * (light + 0.25), gl_Color.a);
    coord0 = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    coord1 = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
}
