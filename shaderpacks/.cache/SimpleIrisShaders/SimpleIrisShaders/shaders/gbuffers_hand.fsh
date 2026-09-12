/*
    gbuffers_hand.fsh
    ---------------------------------------------------------------
    Pipeline stage: GBUFFERS_HAND (held item/block, first-person)

    Deliberately skips shadow sampling entirely - the held item is
    close to the near plane and moves with camera rotation, which is
    exactly the situation where shadow-map self-shadowing artifacts
    (flickering/peter-panning) are most visible. Vanilla items don't
    need to receive terrain shadows to look right, and skipping the
    shadow-map fetch here is a small free win on every GPU, iGPU
    included, since the hand fills a meaningful chunk of the screen.
    ---------------------------------------------------------------
*/
#version 330 compatibility

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

    float diffuse = halfLambert(normal, lightDir) * lightMapCoord.y;
    vec3 litColor = albedo.rgb * lightmapColor * (0.6 + diffuse * lightColor * 1.2);

    gl_FragColor = vec4(litColor, albedo.a);
}
