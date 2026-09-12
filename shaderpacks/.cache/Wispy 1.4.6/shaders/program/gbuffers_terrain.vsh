#include "/lib/all_the_libs.glsl"
#include "/global/lighting.vsh"

void main() {
    init_generic();

    #ifdef WAVY_PLANTS
    if (ViewPos.z > -64.0) {
        vec3 RelativeWorldPos = mat3(gbufferModelViewInverse) * ViewPos;
        vec3 WavePos = (RelativeWorldPos + cameraPosition) / WAVE_SIZE + (frameTimeCounter * WAVE_SPEED);

        float sinX = sin(WavePos.x);
        float sinY = sin(WavePos.y);
        float sinZ = sin(WavePos.z);
        float Noise = (sinX * sinY * sinZ) * (WAVE_AMPLITUDE + rainStrength * 0.1);

        vec3 offset = vec3(0.0);
        bool isTop = gl_MultiTexCoord0.t < mc_midTexCoord.t;

        if (material == 10003.0) { // Leaves
            offset = vec3(Noise * 0.5, -Noise * 0.5, -Noise * 0.5);
        } else if (material >= 10004.0 && material <= 10006.0) {
            bool isTallPlant = (material == 10005.0 || material == 10006.0);
            float moveMask = 1.0;

            if (isTallPlant) {
                moveMask = isTop ? 1.0 : 0.5;
            } else {
                moveMask = 1.0;
            }

            offset = vec3(Noise * moveMask);
        }

        ViewPos += mat3(gbufferModelView) * offset;
        gl_Position = gl_ProjectionMatrix * vec4(ViewPos, 1.0);
    }
    #endif

    #if TAA_MODE >= 2
    gl_Position.xy += taaJitter * gl_Position.w;
    #endif
}
