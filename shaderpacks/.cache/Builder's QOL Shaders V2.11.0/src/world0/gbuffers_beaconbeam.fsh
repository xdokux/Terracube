#version 120

#include "lib/defines.glsl"

uniform float frameTimeCounter;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform sampler2D texture;
uniform vec3 actualCameraPosition;

#ifdef FANCY_BEACONS
	varying vec2 beaconPosPlayer;
#endif
#ifndef FANCY_BEACONS
	varying vec2 texcoord;
#endif
#ifdef FANCY_BEACONS
	varying vec3 vPosPlayer;
#endif
varying vec4 tint;

#include "/lib/goldenOffsets.glsl"

#include "/lib/math.glsl"

#include "/lib/beaconMethods.glsl"

void main() {
	#include "/lib/beacon.fsh"

/* DRAWBUFFERS:04 */
	gl_FragData[0] = color; //gcolor
	gl_FragData[1] = vec4(0.96875, 0.96875, 1.0, 1.0); //gaux1
}