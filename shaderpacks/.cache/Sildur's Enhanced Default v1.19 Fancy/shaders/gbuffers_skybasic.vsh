#version 120

#if MC_VERSION < 11700
varying vec4 color;
varying float dist;
#else
varying vec4 glColor;
#endif

void main() {
	gl_Position = ftransform();
#if MC_VERSION < 11700
	gl_FogFragCoord = gl_Position.z;
	color = gl_Color;
	dist = length(gl_ModelViewMatrix * gl_Vertex);
#else
	glColor = vec4(gl_Color.rgb, float(gl_Color.r == gl_Color.g && gl_Color.g == gl_Color.b && gl_Color.r > 0.0)); 	//rgb = star color, a = flag for weather or not this pixel is a star.
#endif
}