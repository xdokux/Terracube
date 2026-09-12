#include "/lib/all_the_libs.glsl"
#include "/generic/water.glsl"
in vec2 texcoord;
in vec4 glcolor;

flat in vec3 Normal;
flat in float Material;

in vec3 PlayerPos;

#ifdef RSM
    /* RENDERTARGETS:0,2,1 */
#else
    /* RENDERTARGETS:0,2 */
#endif
layout(location = 0) out vec4 Color;
layout(location = 1) out vec4 MaterialBuf;
#ifdef RSM
    layout(location = 2) out vec4 ShadowNormal;
#endif

void main() {
    Color = texture(gtexture, texcoord) * glcolor;
    if (Color.a < 0.1) {
        discard;
        return;
    }

    if (Material == MATERIAL_WATER) {
        vec3 ScreenPos = vec3(gl_FragCoord.xy * shadowTexSize, gl_FragCoord.z);

        float Depth = gl_FragCoord.z;
        float Depth1 = texture(shadowtex1, ScreenPos.xy).x;

        vec3 ShadowPosUndistorted = undistort(ScreenPos * 2 - 1);
        vec3 NDCPos = vec3(ShadowPosUndistorted);
        vec3 NDCPos1 = vec3(ShadowPosUndistorted.xy, (Depth1 * 2 - 1) / 0.2);
        vec3 ViewPos = project_and_divide(shadowProjectionInverse, NDCPos);
        vec3 ViewPos1 = project_and_divide(shadowProjectionInverse, NDCPos1);

        float WaterFog = min(1, exp(-distance(ViewPos, ViewPos1) * 0.3));

        Color.rgb = 1 - srgb_linear(WaterAbsorbtion);
        
        Color.a = 1 - WaterFog;
        MaterialBuf.r = 1;
        #ifdef RSM
            ShadowNormal.rg = vec2(0, -1);
        #endif
    } else {
        Color.rgb = srgb_linear(Color.rgb);
        #ifdef RSM
            ShadowNormal.rg = encodeUnitVector(Normal) * 0.5 + 0.5;
        #endif
        MaterialBuf.r = 0;
    }
}
