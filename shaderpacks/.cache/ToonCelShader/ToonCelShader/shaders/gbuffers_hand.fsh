#version 330 compatibility
/* DRAWBUFFERS:01 */

#include "lib/settings.glsl"
#include "lib/common.glsl"
#include "lib/lighting.glsl"

uniform sampler2D texture;
uniform sampler2D lightmap;

varying vec2 texCoord;
varying vec2 lightMapCoord;
varying vec3 normal;
varying vec4 vertexColor;

void main() {
    vec4 albedo = texture2D(texture, texCoord) * vertexColor;
    if (albedo.a < 0.1) discard;

    vec3 lightDir = getShadowLightDirection();
    float dayFactor = getDayFactor(lightDir);
    vec3 lightColor = getSunMoonColor(dayFactor);
    vec3 lightmapColor = texture2D(lightmap, lightMapCoord).rgb;

    float banded = bandedDiffuse(normal, lightDir) * lightMapCoord.y;
    vec3 litColor = albedo.rgb * lightmapColor * (0.4 + banded * lightColor * 0.8);
    litColor = adjustSaturation(litColor, SATURATION);

    gl_FragData[0] = vec4(litColor, albedo.a);
    // Neutral/flat normal for the hand - it's always close to camera
    // and moves with view rotation, which would otherwise paint a
    // constantly-shifting false outline across it every frame.
    gl_FragData[1] = vec4(0.5, 0.5, 1.0, 1.0);
}
