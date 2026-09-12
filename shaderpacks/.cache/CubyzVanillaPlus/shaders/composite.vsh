// composite.vsh - fullscreen-quad passthrough, standard for post passes.

varying vec2 texcoord;

void main() {
	gl_Position = gl_ProjectionMatrix * gl_ModelViewMatrix * gl_Vertex;
	texcoord = gl_MultiTexCoord0.xy;
}
