#include "/lib/all_the_libs.glsl"

out vec2 texcoord;
out float DepthCenterL;
out float DepthCenter;

void main() {
	gl_Position = ftransform();
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;

	#ifdef DOF_MANUAL_FOCUS
        DepthCenterL = DOF_FOCUS_DISTANCE;
    #else
        bool IsDH;
        DepthCenter = get_depth(vec2(0.5), IsDH);

        float OldDepth = dataBuf.DofFocus;
        float BlendFactor = frameTime / (1 + frameTime) * DOF_FOCUS_ADJUSTMENT_SPEED;
        DepthCenter = mix(OldDepth, DepthCenter, BlendFactor);

        DepthCenterL = l_depth(DepthCenter, IsDH);
    #endif
}
