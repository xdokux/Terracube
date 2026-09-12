#version 330 compatibility

#include "lib/settings.glsl"
#include "lib/common.glsl"
#include "lib/lighting.glsl"
#include "lib/shadows.glsl"

uniform sampler2D texture;
uniform sampler2D lightmap;
uniform vec4 entityColor;
uniform float far;

varying vec2 texCoord;
varying vec2 lightMapCoord;
varying vec3 normal;
varying vec3 viewPos;
varying vec4 vertexColor;

void main() {
    vec4 albedo = texture2D(texture, texCoord) * vertexColor;
    if (albedo.a < 0.1) discard;
    albedo.rgb = mix(albedo.rgb, entityColor.rgb, entityColor.a);

    vec3 lightDir = getShadowLightDirection();
    float dayFactor = getDayFactor(lightDir);
    vec3 lightColor = getSunMoonColor(dayFactor);
    vec3 lightmapColor = tintBlockLight(texture2D(lightmap, lightMapCoord).rgb, lightMapCoord.x, -1.0);

    float diffuse = halfLambert(normal, lightDir);
    float shadow = sampleShadow(viewPos);
    float skyVisibility = lightMapCoord.y;
    float directLight = diffuse * shadow * skyVisibility;
    float ambient = max(MIN_AMBIENT, (1.0 - skyVisibility) * 0.03);

    vec3 litColor = albedo.rgb * lightmapColor * (ambient + directLight * lightColor * 1.4);

    float dist = length(viewPos);
    float fogAmount = expFog(dist, far * 0.7, far);
    vec3 fogColorAdjusted = mix(gl_Fog.color.rgb, lightColor * 0.6, 0.35);
    litColor = mix(litColor, fogColorAdjusted, fogAmount);

    gl_FragColor = vec4(litColor, albedo.a);
}
