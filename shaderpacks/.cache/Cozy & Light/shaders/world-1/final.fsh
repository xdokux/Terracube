#version 330 compatibility

uniform sampler2D colortex0;
uniform float playerMood;

in vec2 texcoord;

mat3 aces_input_matrix = mat3(
    vec3(0.59719f, 0.35458f, 0.04823f),
    vec3(0.07600f, 0.90834f, 0.01566f),
    vec3(0.02840f, 0.13383f, 0.83777f)
);

mat3 aces_output_matrix = mat3(
    vec3( 1.60475f, -0.53108f, -0.07367f),
    vec3(-0.10208f,  1.10813f, -0.00605f),
    vec3(-0.00327f, -0.07276f,  1.07602f)
);

vec3 mul(mat3 m, vec3 v) {
    float x = m[0][0] * v[0] + m[0][1] * v[1] + m[0][2] * v[2];
    float y = m[1][0] * v[1] + m[1][1] * v[1] + m[1][2] * v[2];
    float z = m[2][0] * v[1] + m[2][1] * v[1] + m[2][2] * v[2];
    return vec3(x, y, z);
}

vec3 rtt_and_odt_fit(vec3 v) {
    vec3 a = v * (v + 0.0245786f) - 0.000090537f;
    vec3 b = v * (0.983729f * v + 0.4329510f) + 0.238081f;
    return a / b;
}

vec3 aces_fitted(vec3 v) {
    v = mul(aces_input_matrix, v);
    v = rtt_and_odt_fit(v);
    return mul(aces_output_matrix, v);
}

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outColor0;

void main() {
	vec4 color = texture(colortex0, texcoord);

    //color = vec4(vec3(playerMood), 1.0);

    //color.rgb = aces_fitted(color.rgb);

    outColor0 = color;
}