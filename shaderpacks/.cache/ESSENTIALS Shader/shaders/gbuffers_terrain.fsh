#version 120

/* DRAWBUFFERS:01 */
#define ABOUT_ESSENTIALS 1 // [1]#if ABOUT_ESSENTIALS == 1#endif

uniform sampler2D gtexture;
uniform sampler2D lightmap;
uniform float alphaTestRef;
uniform vec3 sunPosition;
uniform float frameTimeCounter;

varying vec2 lmcoord;
varying vec2 texcoord;
varying vec4 glcolor;
varying vec3 viewPos;
varying vec3 worldNormal;
varying float blockId;

bool isIce(float id) {
    return id == 79.0 || id == 174.0 || id == 212.0;
}

bool isGlass(float id) {
    return id == 20.0 || id == 95.0 || id == 102.0 || id == 160.0;
}

void main() {
    vec4 color = texture2D(gtexture, texcoord) * glcolor;
    if (color.a < alphaTestRef) discard;

    color *= texture2D(lightmap, lmcoord);

    bool ice   = isIce(blockId);
    bool glass = isGlass(blockId);

    if (ice || glass) {
        vec3 normal  = normalize(worldNormal);
        vec3 viewDir = normalize(-viewPos);
        vec3 sunDir  = normalize(sunPosition);

        float t = frameTimeCounter;

        if (ice) {
            float nx = sin(t * 0.3 + texcoord.x * 4.0) * 0.015;
            float nz = cos(t * 0.25 + texcoord.y * 4.0) * 0.015;
            normal = normalize(normal + vec3(nx, 0.0, nz));
        }

        vec3 halfDir    = normalize(sunDir + viewDir);
        float NdotH     = max(dot(normal, halfDir), 0.0);
        float shininess = ice ? 64.0 : 32.0;
        float spec      = pow(NdotH, shininess);
        float intensity = ice ? 0.3 : 0.15;

        float NdotV  = max(dot(normal, viewDir), 0.0);
        float fresnel = pow(1.0 - NdotV, 3.0);
        spec *= mix(intensity, intensity * 2.0, fresnel);

        vec3 specColor = ice ? vec3(0.85, 0.93, 1.0) : vec3(1.0, 0.98, 0.95);
        color.rgb += specColor * spec;
    }

    gl_FragData[0] = color;
    gl_FragData[1] = vec4(lmcoord, 0.0, 1.0);
}