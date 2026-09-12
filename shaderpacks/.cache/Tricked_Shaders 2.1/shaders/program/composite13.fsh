#include "/lib/all_the_libs.glsl"

in vec2 texcoord;

/* DRAWBUFFERS:0 */
layout(location = 0) out vec4 Color;

const bool colortex0MipmapEnabled = true;

float calc_CoC(float Depth, float DepthCenter) {
    float focalLength = DepthCenter / (DepthCenter + 1);

    float CoC = abs(DOF_APERTURE_SIZE * (focalLength * (Depth - DepthCenter)) /
          (Depth * (DepthCenter - focalLength)));
    return CoC;
}

vec3 blur_dof(vec2 texcoord, float CoC) {
    vec3 Sum = vec3(0);
	CoC *= gbufferProjection[1][1] / 1.37; // Scale according to fov
	vec2 Radius = resolutionInv * CoC;

    for(int i = 0; i < DOF_BLUR_QUALITY; i++) {
        vec2 Offset = vogel_disk[i] * Radius;
		float lod = log2(CoC * 0.5);
        Sum += textureLod(colortex0, texcoord + Offset, lod).rgb;
    }

    return Sum / DOF_BLUR_QUALITY;
}

void main() {
    float Depth = texture(depthtex0, texcoord).r;
    float DepthL = ld_exact(Depth, false);

    #ifdef DOF_MANUAL_FOCUS
        float DepthCenterL = DOF_FOCUS_DISTANCE;
    #else
        float DepthCenterL = ld_exact(centerDepthSmooth, false);
    #endif

    float CoC = calc_CoC(DepthL, DepthCenterL);
    CoC = Depth < 0.56 ? min(10, CoC) : min(25, CoC);
    
    Color = vec4(blur_dof(texcoord, CoC), 1);

	#ifdef DOF_SHOW_FOCUS
		if(!hideGUI)
			Color.g += float(abs(DepthL - DepthCenterL) < 0.2);
	#endif
}
