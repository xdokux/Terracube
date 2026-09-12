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
    
    // Entities are NEVER emissive (fixes golem eyes issue)
    float emissive = 0.0;
    
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
    
    gl_FragData[0] = vec4(albedo.rgb, 1.0);
    gl_FragData[1] = vec4(worldNormal * 0.5 + 0.5, skyLight);
    gl_FragData[2] = vec4(blockLight, emissive, 0.0, 1.0);
    gl_FragData[3] = vec4(0.0, 0.0, 0.0, 1.0);
    gl_FragData[4] = vec4(albedo.rgb, 1.0); // Scene color for glass
    gl_FragData[5] = vec4(smoothness, metalness, pbrEmissive, 1.0); // colortex5
}
