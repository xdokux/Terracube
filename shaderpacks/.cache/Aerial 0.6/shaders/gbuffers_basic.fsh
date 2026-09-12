#version 120
varying vec4 glcolor;
void main() {
/* DRAWBUFFERS:015 */
    gl_FragData[0] = glcolor;
    gl_FragData[1] = vec4(0.5, 0.5, 1.0, 0.4); // never the emissive path (kills black outline quads)
    gl_FragData[2] = vec4(1.0, 1.0, 0.0, 1.0);
}
