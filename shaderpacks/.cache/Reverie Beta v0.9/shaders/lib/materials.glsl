#define MATERIAL_WATER 4
#define MATERIAL_SSS_WEAK 5
#define MATERIAL_SSS_STRONG 6
#define MATERIAL_TALL_PLANT_LOWER 7
#define MATERIAL_TALL_PLANT_UPPER 8
#define MATERIAL_SHORT_PLANT 9
#define MATERIAL_LEAVES 10
#define MATERIAL_FLOODFILL_PASSTHROUGH 20

struct MaterialProperties {
    vec3 Albedo, Normal, FlatNormal;
    vec2 Lightmap;
    float SSS, Id, Smoothness, Emissiveness, F0, chunkFade;
};

float hardcoded_smoothness(float Material) {
    int Mat = int(Material);
    switch (Mat) {
        case 4:
        return 0.9;
    }
    return 0;
}

float get_smoothness(float Smoothness, float Material) {
    float HS = hardcoded_smoothness(Material);
    if (HS != 0) return HS;

    #ifndef PBR_SPECULAR
        return 0;
    #endif

    return Smoothness;
}

float smoothness_to_roughness(float Smoothness) {
    return pow2(1 - Smoothness);
}

float hardcoded_f0(float Material) {
    int Mat = int(Material);
    switch (Mat) {
        case 4:
        return 0.02;
    }
    return 0;
}

const mat2x3 hardcoded_metals[8] = mat2x3[8](
        mat2x3(vec3(2.9114, 2.9497, 2.5845), vec3(3.0893, 2.9318, 2.7670)),
        mat2x3(vec3(0.18299, 0.42108, 1.3734), vec3(3.4242, 2.3459, 1.7704)),
        mat2x3(vec3(1.3456, 0.96521, 0.61722), vec3(7.4746, 6.3995, 5.3031)),
        mat2x3(vec3(3.1071, 3.1812, 2.3230), vec3(3.3314, 3.3291, 3.1350)),
        mat2x3(vec3(0.27105, 0.67693, 1.3164), vec3(3.6092, 2.6248, 2.2921)),
        mat2x3(vec3(1.9100, 1.8300, 1.4400), vec3(3.5100, 3.4000, 3.1800)),
        mat2x3(vec3(2.3757, 2.0847, 1.8453), vec3(4.2655, 3.7153, 3.1365)),
        mat2x3(vec3(0.15943, 0.14512, 0.13547), vec3(3.9291, 3.1900, 2.3808))
    );
const vec3 f0_metals[8] = vec3[8](
    vec3(0.531229, 0.512357, 0.495829),
    vec3(0.94423, 0.776102, 0.373402),
    vec3(0.912298, 0.913851, 0.919681),
    vec3(0.555597, 0.554537, 0.554779),
    vec3(0.925952, 0.720902, 0.504154),
    vec3(0.632484, 0.625937, 0.641479),
    vec3(0.678849, 0.642401, 0.58841),
    vec3(0.962, 0.949468, 0.922115)
);

const vec3 f82_metals[8] = vec3[8](
    vec3(0.571176, 0.563019, 0.579868),
    vec3(0.953362, 0.878628, 0.657227),
    vec3(0.841355, 0.861669, 0.890982),
    vec3(0.56899, 0.564963, 0.61487),
    vec3(0.93419, 0.82521, 0.693799),
    vec3(0.668532, 0.672942, 0.712402),
    vec3(0.653234, 0.658767, 0.660995),
    vec3(0.962272, 0.961263, 0.958359)
);

mat2x3 get_reflectance(float PackF0, float Id, vec3 Color, out bool IsMetal, out bool IsHardcodedMetal) {
    float F0 = hardcoded_f0(Id);
    #ifdef PBR_SPECULAR
        if (F0 == 0) {
            F0 = PackF0;
        }
    #endif
    uint F0ui = uint(F0 * 255);
    IsMetal = F0ui >= 230;
    IsHardcodedMetal = IsMetal && F0ui <= 237;
    if (F0ui == 255) {
        return mat2x3(Color, vec3(0));
    }
    else if (IsHardcodedMetal) {
        return mat2x3(f0_metals[F0ui - 230], f82_metals[F0ui - 230]);
        // return hardcoded_metals[F0ui - 230];
    }
    else {
        return mat2x3(vec3(F0), vec3(0));
    }
}

// Only for use in gbuffers
vec3 get_normal(vec2 Texcoord, vec2 dCoordx, vec2 dCoordy) {
    #ifndef PBR_NORMAL
        return vec3(0, 0, 1);
    #endif

    vec3 Normal;
    #ifdef PBR_POM
        Normal.xy = textureGrad(normals, Texcoord.xy, dCoordx, dCoordy).xy * 2 - 1;
    #else
        Normal.xy = texture(normals, Texcoord.xy).xy * 2 - 1;
    #endif
    Normal.z = sqrt(max(0, 1 - dot(Normal.xy, Normal.xy)));
    return Normal;
}

float get_sss(vec2 Texcoord) {
    #ifdef PBR_SSS
    float PackSSS = texture(specular, Texcoord).z;
    #else
    float PackSSS = 0;
    #endif
    return PackSSS;
} 

float get_emissiveness(vec2 Texcoord) {
    #ifdef PBR_EMISSIVENESS
    float Emissiveness = texture(specular, Texcoord).w;
    #else
    float Emissiveness = 0;
    #endif
    return Emissiveness;
} 


// For use in deferred and later
// Decodes all data from colortex1 and colortex2
MaterialProperties unpack_material(mat2x4 GbufferData, bool IsDH) {
    vec4 Data = GbufferData[0];
    vec4 Data2 = GbufferData[1];

    vec2 UnpackX = unpackUnorm2x8(Data.x);
    vec2 UnpackY = unpackUnorm2x8(Data.y);

    MaterialProperties NewMat;

    NewMat.Albedo = vec3(UnpackX, UnpackY.x);
    NewMat.Albedo = srgb_linear(NewMat.Albedo);

    NewMat.Id = UnpackY.y * 255;

    vec2 UnpackZ = unpackUnorm2x8(Data.z);
    NewMat.Smoothness = UnpackZ.x;
    NewMat.F0 = UnpackZ.y;

    NewMat.Normal = decodeUnitVector(unpackUnorm2x8(Data.w) * 2 - 1);
    NewMat.Normal = player_view(NewMat.Normal, IsDH);

    NewMat.Lightmap = unpackUnorm2x8(Data2.x);

    NewMat.chunkFade = Data2.y;

    vec2 Unpack2Z = unpackUnorm2x8(Data2.z);
    NewMat.SSS = Unpack2Z.x;
    NewMat.Emissiveness = Unpack2Z.y;

    NewMat.FlatNormal = decodeUnitVector(unpackUnorm2x8(Data2.w) * 2 - 1);
    NewMat.FlatNormal = player_view(NewMat.FlatNormal, IsDH);

    return NewMat;
}

vec4 pack_material_buf1(MaterialProperties Mat, bool IsDH) {
    vec4 Data;
    Data.x = packUnorm2x8(clamp(Mat.Albedo.rg, 0, 1));
    Data.y = packUnorm2x8(clamp(vec2(Mat.Albedo.b, Mat.Id / 255), 0, 1));
    Data.z = packUnorm2x8(clamp(vec2(Mat.Smoothness, Mat.F0), 0, 1));
    Data.w = packUnorm2x8(clamp(encodeUnitVector(view_player(Mat.Normal, IsDH)) * 0.5 + 0.5, 0, 1));
    return Data;
}

vec4 pack_material_buf2(MaterialProperties Mat, bool IsDH) {
    vec4 Data;
    Data.x = packUnorm2x8(clamp(Mat.Lightmap, 0, 1));
    Data.y = Mat.chunkFade;
    Data.z = packUnorm2x8(clamp(vec2(Mat.SSS, Mat.Emissiveness), 0, 1));
    Data.w = packUnorm2x8(clamp(encodeUnitVector(view_player(Mat.FlatNormal, IsDH)) * 0.5 + 0.5, 0, 1));
    return Data;
}