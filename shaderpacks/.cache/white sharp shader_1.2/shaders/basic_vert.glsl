#version 300

in vec3 vaPosition;
in vec2 vaUV0;
in vec4 vaColor;
in ivec2 vaUV2;
in vec3 vaNormal;

uniform vec3 chunkOffset;
uniform mat4 modelViewMatrix;
uniform mat4 projectionMatrix;
uniform vec3 cameraPosition;
uniform mat4 gbufferModelViewInverse;
uniform mat3 normalMatrix;

out vec2 texCoord;
out vec3 foliageColor;
out vec2 lightMapCoords;
out vec3 geoNormal;

void main() {
    geoNormal = vaNormal;

    texCoord = vaUV0;
    foliageColor = vaColor.rgb;
    lightMapCoords = vaUV2 * (1.0 / 256.0) + (1.0 /32.0);

    gl_Position = projectionMatrix *  modelViewMatrix * vec4(vaPosition+chunkOffset,1);

}