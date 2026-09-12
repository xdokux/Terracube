#include "/lib/all_the_libs.glsl"

in vec2 texcoord;
in float DepthCenterL;
in float DepthCenter;

/* RENDERTARGETS:0 */
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

    for(int i = 0; i < 32; i++) {
        vec2 Offset = vogel_disk[i] * Radius;
		float lod = log2(CoC * 0.3333);
        Sum += textureLod(colortex0, texcoord + Offset, lod).rgb;
    }

    return Sum / 32;
}

void main() {

    bool IsDH;
    float Depth = get_depth(texcoord, IsDH);
    float DepthL = l_depth(Depth, IsDH);

    float CoC = calc_CoC(DepthL, DepthCenterL);
    CoC = Depth < 0.56 ? min(10, CoC) : min(50, CoC);
    
    Color = vec4(blur_dof(texcoord, CoC), 1);

    #ifdef DOF_SHOW_FOCUS
        if(!hideGUI)
            Color.g += float(abs(DepthL - DepthCenterL) < 0.2);
    #endif

    if(all(lessThan(gl_FragCoord.xy, vec2(1)))) {
        dataBuf.DofFocus = DepthCenter;
    }
}
