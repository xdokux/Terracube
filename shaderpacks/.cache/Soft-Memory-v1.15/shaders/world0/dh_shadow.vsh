#version 460 compatibility

in vec3 vaPosition;

uniform mat4 shadowModelView;
uniform mat4 shadowProjection;

void main() {
    gl_Position = shadowProjection * shadowModelView * vec4(vaPosition, 1.0);
}
