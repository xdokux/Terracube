#version 120

// GamesofDev is non chalant
varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 glColor;
varying vec3 normal;
varying vec3 worldPos;
varying vec3 viewPos;

attribute float mc_Entity;
varying float blockId;

attribute vec4 at_tangent;
varying vec3 tangent;
varying vec3 binormal;

uniform vec3 cameraPosition;

void main() {
    gl_Position = ftransform();
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    glColor = gl_Color;
    normal = normalize(gl_NormalMatrix * gl_Normal);
    tangent = normalize(gl_NormalMatrix * at_tangent.xyz);
    binormal = cross(normal, tangent) * at_tangent.w;
    viewPos = (gl_ModelViewMatrix * gl_Vertex).xyz;
    worldPos = gl_Vertex.xyz + cameraPosition;
    
    blockId = mc_Entity;
}
