out Data {
    vec2 lmcoord;
    vec2 texcoord;
    vec4 glcolor;
    flat float Id;
    flat mat3 TBN;
    vec3 ViewPos;
    float chunkFade;
    #if (defined PBR_POM) && (defined GBUFFERS_TERRAIN)
        flat vec2 AtlasScale;
        flat vec2 AtlasOffset;
        vec2 LocalPos;
        vec3 TangentPos;
    #endif
} DataOut;

attribute vec4 at_midBlock;
attribute vec2 mc_Entity;
attribute vec4 at_tangent;
attribute vec4 mc_midTexCoord;

mat3 get_tbn_matrix() {
	mat3 tbn;
	tbn[0] = mat3(gbufferModelViewInverse) * normalize(gl_NormalMatrix * at_tangent.xyz);
	tbn[2] = mat3(gbufferModelViewInverse) * normalize(gl_NormalMatrix * gl_Normal);
	tbn[1] = cross(tbn[0], tbn[2]) * sign(at_tangent.w);
	return tbn;
}

void init_generic() {
    gl_Position = ftransform();

    gl_Position.xy += taaJitter * gl_Position.w;

    DataOut.texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    DataOut.lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    DataOut.lmcoord = max(DataOut.lmcoord * 1.06667 - 0.0648, 0);
    
    DataOut.glcolor = gl_Color;
    DataOut.Id = mc_Entity.x - 10000.0;
    #ifdef DH_TERRAIN
        switch(dhMaterialId) {
        case DH_BLOCK_WATER:
            DataOut.Id = MATERIAL_WATER;
            break;
        case DH_BLOCK_LEAVES:
            DataOut.Id = MATERIAL_LEAVES;
            break;
        default:
            DataOut.Id = 0;
            break;
        }
    #endif
    DataOut.TBN[0] = normalize(gbufferModelView[0].xyz);
    DataOut.TBN[1] = normalize(gbufferModelView[2].xyz);
    DataOut.TBN[2] = normalize(gl_NormalMatrix * gl_Normal);

    DataOut.ViewPos = (gl_ModelViewMatrix * gl_Vertex).xyz;

    #ifdef IRIS_FEATURE_FADE_VARIABLE
        DataOut.chunkFade = mc_chunkFade == -1 ? 1 : mc_chunkFade;
    #endif

    #if (defined PBR_POM) && (defined GBUFFERS_TERRAIN)
        vec2 midcoord = (gl_TextureMatrix[0] *  mc_midTexCoord).xy;
        DataOut.AtlasScale = abs(DataOut.texcoord - midcoord) * 2;
        DataOut.AtlasOffset = min(DataOut.texcoord, 2 * midcoord - DataOut.texcoord);
        DataOut.LocalPos = sign(DataOut.texcoord - midcoord) * 0.5 + 0.5;
        DataOut.TangentPos = view_player(DataOut.ViewPos, false) * get_tbn_matrix();
    #endif
}
