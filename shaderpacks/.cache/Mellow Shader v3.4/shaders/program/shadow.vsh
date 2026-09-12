#include "/lib/all_the_libs.glsl"
#include "/global/voxelisation.glsl"
attribute vec4 mc_Entity;
attribute vec2 mc_midTexCoord;
attribute vec4 at_midBlock;

out vec2 texcoord;
out vec4 glcolor;
flat out float material;

void main() {
	texcoord = get_texcoord(gl_TextureMatrix[0], gl_MultiTexCoord0);
	glcolor = gl_Color;
    material = mc_Entity.x;

   
	vec3 ViewPos = (gl_ModelViewMatrix * gl_Vertex).xyz;

	#ifdef WAVY_PLANTS
    if (ViewPos.z > -64 && material >= 10002 && material <= 10006 && material != 10003) {
        vec3 WorldPos = (shadowModelViewInverse * vec4(ViewPos, 1)).xyz;
        WorldPos += cameraPosition;
        vec3 WavePos = WorldPos / WAVE_SIZE + frameTimeCounter * WAVE_SPEED + linstep(100, 150, WorldPos.y) * 0.1;
        WavePos = sin(WavePos);
        float Noise = WavePos.x * WavePos.y * WavePos.z;
        Noise *= WAVE_AMPLITUDE + rainStrength * 0.1;
        #ifdef WAVE_LEAVES
        if (material == 10002) {
            WorldPos.x += Noise / 2;
            WorldPos.z -= Noise / 2;
        }
        else
        #endif
        if (material == 10004) {
            if (gl_MultiTexCoord0.t < mc_midTexCoord.t)
                WorldPos += Noise;
        }
        else if (material == 10005) {
            if (gl_MultiTexCoord0.t < mc_midTexCoord.t)
                WorldPos += Noise / 2;
        }
        else if (material == 10006) {
            if (gl_MultiTexCoord0.t > mc_midTexCoord.t)
                WorldPos += Noise / 2;
            else
                WorldPos += Noise;
        } 
        else if(material == 10001) {
            if(fract(WorldPos.y + 0.005) > 0.15) {
                WorldPos.y += Noise;
            }
        }

        WorldPos -= cameraPosition;

        #if SUN_PATH_ROTATION == 0
            if((material == 10004 || material == 10005) && texcoord.y < mc_midTexCoord.y) {
                vec3 Normal = normalize(gl_NormalMatrix * gl_Normal);
                WorldPos += Normal * 0.35;
            }
        #endif

        gl_Position = shadowProjection * vec4((shadowModelView * vec4(WorldPos, 1)).xyz, 1);
    } else 
    #endif
        gl_Position = ftransform();
    
    gl_Position.xyz = distort(gl_Position.xyz);

    #ifdef COLORED_LIGHTS
        if(gl_VertexID % 4 == 0 && should_id_be_voxelised(material)) {
            if(renderStage == MC_RENDER_STAGE_TERRAIN_SOLID || renderStage == MC_RENDER_STAGE_TERRAIN_TRANSLUCENT) {
                vec3 MidPos = gl_Vertex.xyz + at_midBlock.xyz / 64.0;
                vec3 PlayerMidPos = (shadowModelViewInverse * vec4((gl_ModelViewMatrix * vec4(MidPos, 1)).xyz, 1)).xyz;
                ivec3 PlayerPosAbs = ivec3(get_voxel_pos(PlayerMidPos));
                if(is_in_voxel_range(PlayerPosAbs)) {
                    vec4 Color = textureLod(gtexture, mc_midTexCoord, 4);
                    
                    // Is light source
                    if(at_midBlock.w > 0.1) {
                        Color.rgb = hardcoded_light_colors(material, Color.rgb); 
                        Color.rgb *= max(0, (at_midBlock.w - 0.5) / 15);
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
}
