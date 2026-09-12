#version 120

// GamesofDev is non chalant
varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 glColor;
varying vec3 normal;

uniform sampler2D texture;
uniform sampler2D specular;
uniform sampler2D normals;

varying vec3 tangent;
varying vec3 binormal;

/* DRAWBUFFERS:012345 */

void main() {
    vec4 albedo = texture2D(texture, texcoord) * glColor;
    if (albedo.a < 0.1) discard;
    
    vec3 N = normalize(normal);
    float blockLight = lmcoord.x;
    float skyLight = lmcoord.y;
    
    // LabPBR Support
    vec3 worldNormal = N;
    float smoothness = 0.0;
    float metalness = 0.0;
    float pbrEmissive = 0.0;
    
    vec4 specData = texture2D(specular, texcoord);
    smoothness = specData.r;
    metalness = specData.g;
    pbrEmissive = specData.b;
    
    vec4 normData = texture2D(normals, texcoord);
    if (length(normData.rgb) > 0.01) {
        vec3 normalMap = normData.rgb * 2.0 - 1.0;
        mat3 TBN = mat3(tangent, binormal, N);
        worldNormal = normalize(TBN * normalMap);
    }
    
    // Output standard G-buffer data so composite pass can light it correctly
    // colortex0: Albedo
    gl_FragData[0] = vec4(albedo.rgb, 1.0);
    
    // colortex1: Normal (RGB) + Sky Light (A)
    gl_FragData[1] = vec4(worldNormal * 0.5 + 0.5, skyLight);
    
    // colortex2: Block Light (R) + Emissive (G) + Hand flag (B)
    // Hand is held item, assume simple lighting, no emissive override for now
    gl_FragData[2] = vec4(blockLight, 0.0, 1.0, 1.0);
    
    // colortex3: Light Color (None)
    gl_FragData[3] = vec4(0.0, 0.0, 0.0, 1.0);
    
    // colortex4: Scene color for glass transparency
    gl_FragData[4] = vec4(albedo.rgb, 1.0);
    
    // colortex5: PBR Data
    gl_FragData[5] = vec4(smoothness, metalness, pbrEmissive, 1.0);
}
