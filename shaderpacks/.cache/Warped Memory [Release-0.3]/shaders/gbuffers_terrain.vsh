#version 330 compatibility

uniform mat4 gbufferModelViewInverse;

out vec2 lmcoord;
out vec2 texcoord;
out vec4 glcolor;
out vec3 normal;

void main() {
    gl_Position = ftransform();
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    float shading = 0.6 + 0.4 * abs(gl_Normal.z * 0.5);
    glcolor = gl_Color * vec4(shading, shading, shading, 1.0);

    normal - gl_NormalMatrix * gl_Normal;
    normal = mat3(gbufferModelViewInverse) * normal;
}
