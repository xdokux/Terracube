#include "/lib/all_the_libs.glsl"
#include "/global/post/bloom.glsl"

// Write to bloom buffer
// DONTOPTIMIZE-START
const bool colortex0MipmapEnabled = true;
// DONTOPTIMIZE-END
in vec2 texcoord;

/* DRAWBUFFERS:1 */
layout(location = 0) out vec4 Color;

void main() {
	Color.rgb = blur3x3(colortex0, texcoord).rgb;

    #ifndef DEBUG_DISABLE_NAN_PREVENTION
	if(any(isnan(Color.rgb))) {
        Color.rgb = vec3(0);
    }
    #endif
}
