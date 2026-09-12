#version 120

uniform sampler2D gtexture;
uniform sampler2D lightmap;
uniform vec3 sunPosition;
uniform float alphaTestRef;
uniform float frameTimeCounter;

varying vec2 lmcoord;
varying vec2 texcoord;
varying vec4 glcolor;
varying vec3 viewPos;
varying vec3 worldNormal;
varying float isWater;

void main() {
    if (isWater < 0.5) {
        vec4 vanillaColor = texture2D(gtexture, texcoord) * glcolor;
        vanillaColor *= texture2D(lightmap, lmcoord);
        if (vanillaColor.a < alphaTestRef) discard;
        gl_FragData[1] = vec4(lmcoord, 0.0, 1.0);
        gl_FragData[0] = vanillaColor;
        return;
    }

    vec3 lightmap3 = texture2D(lightmap, lmcoord).rgb;

    float t  = frameTimeCounter;
    float nx = sin(t * 1.1 + texcoord.x * 9.0 + texcoord.y * 4.0) * 0.035
             + sin(t * 0.7 + texcoord.x * 5.0 + texcoord.y * 8.0) * 0.02;
    float nz = cos(t * 0.9 + texcoord.x * 6.0 + texcoord.y * 7.0) * 0.035
             + cos(t * 1.3 + texcoord.x * 4.0 + texcoord.y * 5.0) * 0.02;
    vec3 normal = normalize(vec3(nx, 1.0, nz));

    vec3 viewDir = normalize(-viewPos);
    vec3 sunDir  = normalize(sunPosition);

    float NdotV  = clamp(dot(vec3(0.0, 1.0, 0.0), viewDir), 0.0, 1.0);
    float fresnel = 0.02 + 0.98 * pow(1.0 - NdotV, 3.0);
    fresnel = clamp(fresnel, 0.0, 1.0);

    vec3 deepColor    = vec3(0.02, 0.09, 0.18);
    vec3 shallowColor = vec3(0.07, 0.28, 0.42);
    vec3 waterColor   = mix(deepColor, shallowColor, 0.5);
    waterColor *= lightmap3;

    vec3 halfDir = normalize(sunDir + viewDir);
    float spec   = pow(max(dot(normal, halfDir), 0.0), 48.0);
    waterColor  += vec3(1.0, 0.97, 0.92) * spec * 0.25;

    float alpha = 0.55 + fresnel * 0.1;

    gl_FragData[1] = vec4(lmcoord, 1.0, 1.0);
    gl_FragData[0] = vec4(waterColor, clamp(alpha, 0.55, 0.75));
}