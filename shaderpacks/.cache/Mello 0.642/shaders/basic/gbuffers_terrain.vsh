uniform float viewWidth;
uniform float viewHeight;

out float mask;
out float emission;
out vec2 lmcoord;
out vec2 texcoord;
out vec3 normal;
out vec3 localPos;
out vec4 glcolor;

in vec2 mc_Entity;
in vec4 at_midBlock;

uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;

void main() {
    gl_Position = ftransform();
    glcolor = gl_Color;

    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;

    lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    lmcoord = lmcoord / (30.0 / 32.0) - (1.0 / 32.0);

    normal = gl_NormalMatrix * gl_Normal;
    normal = mat3(gbufferModelViewInverse) * normal;

    localPos = (gbufferModelViewInverse * gl_ModelViewMatrix * gl_Vertex).xyz + cameraPosition;

    emission = at_midBlock.w;
    mask = mc_Entity.x;
}