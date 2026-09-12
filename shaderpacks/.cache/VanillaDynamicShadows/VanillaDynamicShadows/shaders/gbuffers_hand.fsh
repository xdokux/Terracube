#version 330 compatibility
// No shadow sampling here, on purpose - see lib/shadows.glsl's
// comment on gbuffers_terrain for the general technique, but the
// held item specifically is the worst-case surface for shadow-map
// self-flicker (close to camera, moves with every view rotation), so
// it's simplest and most stable to just light it without shadows.

#include "lib/settings.glsl"
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

    float ndotl = diffuse(normal, lightDir) * lightMapCoord.y;
    vec3 litColor = albedo.rgb * lightmapColor * (MIN_AMBIENT + 0.55 + ndotl * lightColor * 0.5);

    gl_FragColor = vec4(litColor, albedo.a);
}
