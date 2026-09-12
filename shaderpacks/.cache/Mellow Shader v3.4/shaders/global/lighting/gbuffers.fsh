#ifndef VOXY_TERRAIN
    flat in float material;
    in vec2 LightmapCoords;
    in vec2 texcoord;
    in vec4 glcolor;
    in vec3 ViewPos;
    in vec3 Normal;
    in vec4 Tangent;
    flat in vec2 AtlasOffset;
    flat in vec2 AtlasScale;

    flat in vec3 SUN_DIRECT;
    in vec3 SUN_AMBIENT;
    flat in vec3 SKY_TOP;
    flat in vec3 SKY_GROUND;
    
#else
    float material;
    vec2 LightmapCoords;
    vec2 texcoord;
    vec4 glcolor;
    vec3 ViewPos;
    mat3 TBN;
    vec2 AtlasOffset;
    vec2 AtlasScale;
    #include "/global/lighting/light_colors.vsh"

    void map_voxy_param_to_varying(VoxyFragmentParameters param) {
        texcoord = param.uv;
        LightmapCoords = param.lightMap;
        material = param.customId;
        glcolor = param.tinting;
        ViewPos = screen_view(vec3(gl_FragCoord.xy * resolutionInv, gl_FragCoord.z), true);
        // from Cortex
        vec3 normal = vec3(
                        uint((param.face >> 1) == 2),
                        uint((param.face >> 1) == 0),
                        uint((param.face >> 1) == 1)
                    ) *
            (float(int(param.face) & 1) * 2.0 - 1.0);
        if(material >= 10003 && material <= 10006) {
            normal = vxModelView[1].xyz;
        }
        TBN = tbnNormal(player_view(normal, true));
    }
#endif

vec2 dCoordx = dFdx(texcoord), dCoordy = dFdy(texcoord);

#include "/global/atmosphere/sky.glsl"
#include "/global/pbr.glsl"
#include "/global/lighting/shadows.glsl"
#include "/global/water.glsl"
#include "/global/lighting/lighting.glsl"

vec3 get_puddles(vec3 ScreenPos, vec3 ViewPos, vec3 PlayerPos, mat3 TBN, float Dither) {
    float PuddleStrength = wetness; // Only after it's raining
    if(PuddleStrength < 0.01) return vec3(0);

    vec3 WorldPos = PlayerPos + cameraPosition;
    PuddleStrength *= texture(noisetex, WorldPos.xz / 50).r;
    PuddleStrength *= linstep(0.9, 0.95, LightmapCoords.y); // Not in the shade
    PuddleStrength *= step(material, 10002); // Not on grass
    PuddleStrength *= step(0.99, dot(gbufferModelView[1].xyz, TBN[2]));
    PuddleStrength = smoothstep(1 - PUDDLE_COVERAGE, 1 - PUDDLE_COVERAGE + 0.03, PuddleStrength);
    if(PuddleStrength < 0.01) return vec3(0);

    vec4 WaterColor = get_fancy_water(ScreenPos, ViewPos, normalize(ViewPos), PlayerPos, vec4(0), LightmapCoords.y, TBN, Dither, false);
    return WaterColor.rgb * PuddleStrength;
}

#if (defined PBR_POM) && (defined PBR_NORMAL)
    vec2 to_local_pos(vec2 texcoord) {
        return (texcoord - AtlasOffset) / AtlasScale; 
    }

    vec2 from_local_pos(vec2 LocalPos) {
        return fract(LocalPos) * AtlasScale + AtlasOffset;
    }

    // Code by @geforcelegend in #snippets
    mat3 get_tbn(out vec2 TexScale) {
        vec2 dCoordDX = dCoordx;
        vec2 dCoordDY = dCoordy;

        vec3 dPosDX = dFdx(ViewPos);
        vec3 dPosDY = dFdy(ViewPos);

        vec3 normal = cross(dPosDX, dPosDY);

        vec3 tangentHelper = dPosDY * dCoordDX.x - dPosDX * dCoordDY.x;
        vec3 tangent = cross(tangentHelper, normal) / dot(tangentHelper, tangentHelper);

        vec3 bitangentHelper = dPosDY * dCoordDX.y - dPosDX * dCoordDY.y;
        vec3 bitangent = cross(bitangentHelper, normal) / dot(bitangentHelper, bitangentHelper);

        float tangentLen = inversesqrt(dot(tangent, tangent));
        float bitangentLen = inversesqrt(dot(bitangent, bitangent));

        mat3 tbnMatrix = mat3(tangent * tangentLen, bitangent * bitangentLen, normalize(normal));
        TexScale = vec2(tangentLen, bitangentLen);
        return tbnMatrix;
    }

    vec2 pom(mat3 TBN, inout float Shadow) {
        vec2 _TexScale;
        get_tbn(_TexScale);
        
        // Distance fade
        float Dist = len2(ViewPos);
        if(Dist > pow2(12)) return texcoord;

        float Height = 1-textureGrad(normals, texcoord, dCoordx, dCoordy).a;
        if(Height < 1/255.0) {
            return texcoord;
        }

        int StepCount = PBR_POM_STEPS;


        vec3 TangentPos = normalize(ViewPos * TBN);
        vec3 Offset = vec3(TangentPos.xy / -TangentPos.z * PBR_POM_MAX_DEPTH, 1) / StepCount;
        Offset.xy *= _TexScale / AtlasScale;
        float Dither = dither(gl_FragCoord.xy);
        vec3 CurrentPos = vec3(to_local_pos(texcoord) + Offset.xy * Dither, 0); 
        
        for(int i = 0; i < StepCount && Height - CurrentPos.z > 1./255.0; i++) {
            vec2 NewPos = from_local_pos(CurrentPos.xy);            
            Height = 1 - textureGrad(normals, NewPos, dCoordx, dCoordy).a;
            CurrentPos += Offset;
        }
        
        // Need to move back one here
        CurrentPos -= Offset;

        #ifdef POM_SHADOWING
            vec3 OffsetL = normalize(slpN * TBN) * length(Offset) * 2;
            vec3 LightPos = vec3(CurrentPos.xy + OffsetL.xy * max(0.01, Dither), CurrentPos.z);
            float HeightL = 1 - textureGrad(normals, from_local_pos(LightPos.xy), dCoordx, dCoordy).a;
            Shadow = float(LightPos.z - HeightL < 1/255.0);
            Shadow = mix(Shadow, 1, linstep(100, 144, Dist));
        #endif


        return from_local_pos(CurrentPos.xy);
    }
#endif
