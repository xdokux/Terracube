// shadow.vsh
// Renders scene depth from the sun/moon's point of view into shadowtex0/1.
// gl_ModelViewMatrix/gl_ProjectionMatrix are the *shadow* matrices here -
// that's an Iris/OptiFine convention the bridge preserves, not a mistake.

void main() {
	gl_Position = gl_ProjectionMatrix * gl_ModelViewMatrix * gl_Vertex;
}
