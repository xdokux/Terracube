#version 120

varying vec2 uv;
uniform sampler2D depthtex0;
uniform sampler2D colortex3;
uniform sampler2D colortex4;
uniform sampler2D colortex5;
uniform int frameCounter;

/* DRAWBUFFERS:45 */

/*
const int colortex5Format = RGBA32F;
*/

const bool colortex4Clear = false;
const bool colortex5Clear = false;
#define Frames 1

void main() {
    gl_FragData[1] = texture2D(depthtex0, uv);
    if (mod(frameCounter, Frames) == 0) {
        gl_FragData[0] = texture2D(colortex3, uv);
    } else {
        gl_FragData[0] = texture2D(colortex4, uv);
    }
}
