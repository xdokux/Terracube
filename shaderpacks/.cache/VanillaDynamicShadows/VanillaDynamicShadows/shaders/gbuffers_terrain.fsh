#version 330 compatibility

#include "lib/settings.glsl"
#include "lib/common.glsl"
#include "lib/lighting.glsl"
#include "lib/shadows.glsl"

uniform sampler2D texture;
uniform sampler2D lightmap;
uniform float far;

varying vec2 texCoord;
varying vec2 lightMapCoord;
varying vec3 normal;
varying vec3 viewPos;
varying vec4 vertexColor;

void main() {
    vec4 albedo = texture2D(texture, texCoord) * vertexColor;
    if (albedo.a < 0.1) discard;

    vec3 lightDir = getShadowLightDirection();
    float dayFactor = getDayFactor(lightDir);
    vec3 lightColor = getSunMoonColor(dayFactor);
    vec3 lightmapColor = texture2D(lightmap, lightMapCoord).rgb;

    float ndotl = diffuse(normal, lightDir);
    float shadow = sampleShadow(viewPos, normal);
    float skyVisibility = lightMapCoord.y;
    float directLight = ndotl * shadow * skyVisibility;

    float ambient = max(MIN_AMBIENT, (1.0 - skyVisibility) * 0.03);

    // Same overall structure as vanilla's own lighting (lightmap
    // texture handles block/sky light exactly as it always did) -
    // the only addition is the directLight*shadow term darkening
    // areas the sun/moon can't actually reach.
    vec3 litColor = albedo.rgb * lightmapColor * (ambient + 0.55 + directLight * lightColor * 0.5);

    float dist = length(viewPos);
    float fogAmount = expFog(dist, far * 0.8, far);
    litColor = mix(litColor, gl_Fog.color.rgb, fogAmount);

    gl_FragColor = vec4(litColor, albedo.a);
}
