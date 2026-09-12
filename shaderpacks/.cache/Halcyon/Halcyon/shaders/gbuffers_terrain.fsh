#version 120

uniform sampler2D texture;

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 vertexColor;
varying vec3 normal;

/* RENDERTARGETS: 0,1,2 */

void main() {
    vec4 albedo = texture2D(texture, texcoord) * vertexColor;
    if (albedo.a < 0.1) discard;

    vec3 encodedNormal = normalize(normal) * 0.5 + 0.5;

    gl_FragData[0] = vec4(albedo.rgb, 1.0);              // colortex0: albedo
    gl_FragData[1] = vec4(encodedNormal, 0.0);            // colortex1: normal (.a reserved for smoothness)
    gl_FragData[2] = vec4(lmcoord, 0.0, 1.0);             // colortex2: lightmap uv (.a = 1 marks "this pixel is geometry")
}
