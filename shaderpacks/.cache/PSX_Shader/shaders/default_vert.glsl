#version 460 compatibility
#include "/settings.glsl"

uniform bool noise_init;

//Get Entity id.
in float mc_Entity;
in vec4 mc_midTexCoord;

//Model * view matrix and it's inverse.
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;

uniform float far;

uniform vec3 cameraPosition;

//Pass vertex information to fragment shader.
out vec4 color;
out float light;
out float dist_xz;

out vec2 coord0;
out vec2 coord0_mid;

out vec3 vertex_coord0;

out vec2 local_coord0;
out vec4 local_coord0_comp;

out vec2 coord1;

void main()
{
    dist_xz = distance(vec3(gl_Vertex.x, 0, gl_Vertex.z), vec3(0)) / far;

    //Calculate world space position.
    vec3 pos = (gl_ModelViewMatrix * gl_Vertex).xyz;

    if (VSNAP != 0){
        float dist = clamp((pos.z) / -far, 0.0, 1.0);

        vec3 pos_snapped = pos * VSNAP;
        pos_snapped = round(pos_snapped);
        pos_snapped = pos_snapped / VSNAP;

        pos = mix(pos, pos_snapped, dist * (far / 128));
    }

    pos = (gbufferModelViewInverse * vec4(pos,1)).xyz;

    //Output position and fog to fragment shader.
    gl_Position = gl_ProjectionMatrix * gbufferModelView * vec4(pos,1);
    gl_FogFragCoord = length(pos);

    //Calculate view space normal.
    vec3 normal = gl_NormalMatrix * gl_Normal;

    //Use flat for flat "blocks" or world space normal for solid blocks.
    normal = (mc_Entity==1.) ? vec3(0,1,0) : (gbufferModelViewInverse * vec4(normal,0)).xyz;

    //Calculate simple lighting. Thanks to @PepperCode1
    light = min(normal.x * normal.x * 0.6 + normal.y * normal.y * 0.25 * (3.0f + normal.y) + normal.z * normal.z * 0.8, 1.0);

    //Output color with lighting to fragment shader.
    color = gl_Color;
    
    //Output Color texture coordinates to fragment shader.
    coord0 = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;

    //Center Color texture coordinates to fragment shader.
    coord0_mid = (gl_TextureMatrix[0] * mc_midTexCoord).xy;

    vertex_coord0 = gl_Vertex.xyz;

    //Center Relative UV's.
    vec2 coord0_cr = coord0 - coord0_mid;

    //Local UV Coordinates
	local_coord0 = 0.5 + 0.5 * sign(coord0_cr); 

    //Location in Atlas.
	local_coord0_comp.xy  = min(coord0.xy, coord0_mid - coord0_cr);
	
	//Size in Atlas.
	local_coord0_comp.zw  =  abs(coord0_cr)*2.0;

    //Output lightmap coordinates to fragment shader.
    coord1 = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
}
