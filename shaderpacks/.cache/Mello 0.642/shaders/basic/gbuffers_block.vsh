uniform float viewWidth;
uniform float viewHeight;

out float mask;
out vec2 lmcoord;
out vec2 texcoord;
out vec3 normal;
out vec4 glcolor;

uniform int blockEntityId;

uniform mat4 gbufferModelViewInverse;

void main() {
    gl_Position = ftransform();
    glcolor = gl_Color;

    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;

    lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    lmcoord = lmcoord / (30.0 / 32.0) - (1.0 / 32.0);

    normal = gl_NormalMatrix * gl_Normal;
    normal = mat3(gbufferModelViewInverse) * normal;

    mask = blockEntityId;
}