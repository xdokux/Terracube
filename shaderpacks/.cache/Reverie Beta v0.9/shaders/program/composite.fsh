#include "/lib/all_the_libs.glsl"
// Reflection capture

in vec2 texcoord;
#include "/generic/water.glsl"
#include "/generic/sky.glsl"
#include "/generic/clouds.glsl"
#include "/generic/shadow/main.glsl"
#include "/generic/shadow/vl.glsl"

/* RENDERTARGETS:11 */
layout(location = 0) out vec4 Color;
void main() {
    vec3 CapturePos = from_spherical(texcoord);
    vec3 CaptureViewPos = player_view(CapturePos, false);
    vec3 CaptureScreenPos = view_screen(CaptureViewPos, false, true);

    // Is on screen
    if(clamp(CaptureScreenPos.xy, 0, 1) == CaptureScreenPos.xy && CaptureViewPos.z < 0) {
        vec3 Sample = texture(colortex0, CaptureScreenPos.xy).rgb;
        bool IsDH;
        float Depth = get_depth_solid(CaptureScreenPos.xy, IsDH);
        if((Depth <= 0.56) || Depth >= 1) {
            Color = vec4(0, 0, 0, 999999);
        } else {
            Positions Pos = get_positions(CaptureScreenPos.xy, Depth, IsDH, true);

            float Dist = length(Pos.Player);
            Color = vec4(Sample, Dist);
        }
    } else {
        // Approximate previous position?
        float LenToTerrain = texture(colortex11, texcoord).a;
        if(LenToTerrain > farLod) {
            Color = vec4(0, 0, 0, 999999);
        } else {
            float CameraDiff = distance(cameraPosition, previousCameraPosition);
            vec3 PrevCapturePos = normalize(CapturePos * LenToTerrain - cameraPosition + previousCameraPosition);
            vec2 UvDiff = (to_spherical(CapturePos) - to_spherical(PrevCapturePos));

            vec4 PrevData = texture(colortex11, (texcoord + UvDiff), 0);
            float NewLen = length(PrevCapturePos * PrevData.a - cameraPosition + previousCameraPosition);
            Color = vec4(PrevData.rgb, NewLen);
        }
    }
    
}