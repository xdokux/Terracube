#include "/lib/all_the_libs.glsl"
#include "/generic/water.glsl"

#include "/generic/weather.glsl"

attribute vec2 mc_Entity;
attribute vec2 mc_midTexCoord;
attribute vec4 at_midBlock;

out vec2 texcoord;
out vec4 glcolor;

flat out vec3 Normal;
flat out float Material;

out vec3 PlayerPos;

void main() {
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	glcolor = gl_Color;

	Normal = normalize(gl_NormalMatrix * gl_Normal);
	Material = (mc_Entity.x - 10000.0);

	PlayerPos = (shadowModelViewInverse * vec4((gl_ModelViewMatrix * gl_Vertex).xyz, 1)).xyz;

    #ifdef COLORED_LIGHTS
        if(renderStage == MC_RENDER_STAGE_TERRAIN_SOLID) {
            if(gl_VertexID % 4 == 0 && should_id_be_voxelised(Material)) {
                vec3 MidPos = gl_Vertex.xyz + at_midBlock.xyz / 64.0;
                vec3 PlayerMidPos = (shadowModelViewInverse * vec4((gl_ModelViewMatrix * vec4(MidPos, 1)).xyz, 1)).xyz;
                ivec3 PlayerPosAbs = ivec3(get_voxel_pos(PlayerMidPos));
                if(is_in_voxel_range(PlayerPosAbs)) {
                    vec4 Color = textureLod(gtexture, mc_midTexCoord, 4);
                    
                    // Is light source
                    if(at_midBlock.w > 0.1) {
                        Color.rgb = hardcoded_light_colors(Material, Color.rgb); 
                        Color.rgb = max(vec3(0), Color.rgb * (at_midBlock.w - 0.5) / 15);
                        Color.rgb = pow2(Color.rgb);
                        if(frameCounter % 2 == 1) {
                            imageStore(voxelImg_a, PlayerPosAbs, vec4(Color.rgb, 0));
                        } else {
                            imageStore(voxelImg_b, PlayerPosAbs, vec4(Color.rgb, 0));
                        }
                    }
                }
            }
        }
    #endif

    if(Material >= MATERIAL_TALL_PLANT_LOWER && Material <= MATERIAL_LEAVES) {
        vec3 WorldPos = PlayerPos + cameraPosition;
        
        #ifdef WAVY_PLANTS
            WorldPos = get_wavy_plants(WorldPos, Material, gl_MultiTexCoord0.t < mc_midTexCoord.t);
        #endif
        
        gl_Position = shadowProjection * vec4((shadowModelView * vec4((WorldPos - cameraPosition), 1)).xyz, 1);
    } else {
        gl_Position = ftransform();
    }
    gl_Position.xyz = distort(gl_Position.xyz);
}
