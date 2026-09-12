#version 120

#include "lib/defines.glsl"

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
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

#include "/lib/math.glsl"

void main() {
	#include "/lib/beacon.vsh"
}