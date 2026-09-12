/*
const int colortex0Format   = RGBA16F;
const int colortex1Format   = RGBA16;
const int colortex2Format   = RGBA16;
const int colortex3Format   = RGBA16;
const int colortex4Format   = RGBA16F;
const int colortex5Format   = RGBA16F;
const int colortex6Format   = RGBA16F;
const int colortex7Format   = RGBA16;
const int colortex8Format   = RGBA16F;
const int colortex9Format   = R16F;
const int colortex10Format  = RGBA16F;
const int colortex11Format  = RGBA16F;
const int colortex12Format  = RGBA16;
const int colortex13Format  = RGBA16F;
const int colortex14Format  = RG8;

const int shadowcolor0Format   = RGBA16;
const int shadowcolor1Format   = RGBA16;

const vec4 colortex0ClearColor = vec4(0.0, 0.0, 0.0, 1.0);
const vec4 colortex3ClearColor = vec4(0.0, 0.0, 0.0, 0.0);

const bool colortex6Clear   = false;
const bool colortex9Clear   = false;
const bool colortex10Clear  = false;
const bool colortex11Clear  = false;
const bool colortex12Clear  = false;
const bool colortex13Clear  = false;

const int noiseTextureResolution = 256;

C0:     SCENE COLOR
    3x16F   Scene Color         (full)
    1x16    VAO                 (gbuffer -> deferred)

C1:     GDATA 01
    2x16    Scene Normals       (gbuffer -> composite)
    2x8     Block Mapping       (gbuffer -> comp)
    2x8     Lightmaps           (gbuffer -> composite)

C2:     GDATA 02
    2x8     Material Specular   (gbuffer -> comp)
    2x8     Material Extra      (gbuffer -> comp)
    1x8     Material AO         (gbuffer -> comp)
    1x8     POM Shadows         (gbuffer -> comp)
    1x8     Wetness             (gbuffer -> comp)

C3:     FLAT NRM, GDATA FILTER, LIGHTING DATA
    3x16    Flat Normals        (gbuffer -> deferred),

    4x 16Norm GData for Filtering:
        3x16    Scene Normal    (def -> def)
        1x16    Scene Depth     (def -> def)

    2x RGBE8 Lighting:
        3x16F   Direct Sunlight (deferred -> comp)
        3x16    Albedo          (deferred -> comp)

C4:     SKYBOX
    3x16F   Skybox Capture      (prep -> comp)
    1x16    Cloud Shadowmap     (prep -> comp)

C5:     COLOR FLOAT TEMP
         indirectLight  (deferred -> deferred),
         translucentColor (water -> composite),
         fogScatterReconstruction (composite -> composite),
         bloomTiles     (composite -> composite)

C6:     TAA
    3x16 temporalColor  (full)
    1x16 temporalExposure (full)

C7:     COLOR NORM TEMP
    2x RGBE8 Lighting:
        3x16    Direct Sunlight (deferred -> comp)
        3x16    Emission        (deferred -> deferred)

        -> FLIPPED TO C5 IN def_last
        
         fogTransmittanceReconstruction (composite -> composite)

C8:    

C9:   

C10:    REFLECTION CAPTURE
    3x16 reflectionCapture  (full)
    1x16 reflectionCaptureDepth (full)

C11:    GDATA CAPTURE
    3x16 reflectionCaptureAux   (full)

C12:    GDATA HISTORY
    3x16 historyNormals (full)
    1x16 historyDepth   (full)

C13:    INDIRECT ACCUMULATION
    3x16 indirectLightHistory (full)
    1x16 pixelAge       (full)

C14:    AUX
    1x8 weather particles (gbuffers -> composite)
*/