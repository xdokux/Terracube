#version 330 compatibility

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
    vec3 lightmapColor = tintBlockLight(texture2D(lightmap, lightMapCoord).rgb, lightMapCoord.x, -1.0);

    float diffuse = halfLambert(normal, lightDir) * lightMapCoord.y;
    float ambient = max(MIN_AMBIENT, (1.0 - lightMapCoord.y) * 0.03);
    vec3 litColor = albedo.rgb * lightmapColor * (ambient + diffuse * lightColor * 1.2);

    gl_FragColor = vec4(litColor, albedo.a);
}
