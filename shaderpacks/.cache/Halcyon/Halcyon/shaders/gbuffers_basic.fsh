#version 120

uniform sampler2D texture;
uniform sampler2D lightmap;

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 vertexColor;

void main() {
    vec4 albedo = texture2D(texture, texcoord) * vertexColor;
    if (albedo.a < 0.05) discard;

    vec3 light = texture2D(lightmap, lmcoord).rgb;
    gl_FragColor = vec4(albedo.rgb * light, albedo.a);
}
