#version 120
uniform sampler2D texture;
uniform int heldBlockLightValue;
uniform int heldBlockLightValue2;
uniform int worldTime;
varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 glcolor;
varying vec3 viewPos;
void main() {
    vec4 vColor = glcolor;
    vColor.rgb = mix(vec3(1.0), vColor.rgb, 1.3);
    
    vec4 color = texture2D(texture, texcoord) * vColor;
    if (color.a < 0.1) discard;
    int maxLight = max(heldBlockLightValue, heldBlockLightValue2);
    float handLight = 0.0;
    if (maxLight > 0) {
        float dist = length(viewPos);
        float radius = float(maxLight);
        handLight = max(0.0, 1.0 - (dist / radius));
        handLight = handLight * handLight;
    }
    float blockLight = max(lmcoord.x, handLight);
    vec3 torchColor = vec3(1.0, 0.65, 0.3) * pow(blockLight, 2.0) * 1.2;
    
    float skyExposure = pow(lmcoord.y, 1.3);
    
    float timeVal = (float(worldTime) - 6000.0) / 24000.0 * 6.2831853;
    float sunCos = cos(timeVal);
    float dayFactor = clamp(sunCos * 1.0 + 0.1, 0.02, 1.0);
    vec3 sunLight = vec3(0.95, 0.92, 0.88) * skyExposure;
    vec3 moonLight = vec3(0.15, 0.18, 0.28) * skyExposure;
    vec3 naturalLight = mix(moonLight, sunLight, dayFactor);
    vec3 ambientLight = mix(vec3(0.05, 0.06, 0.08), vec3(0.30, 0.31, 0.34), dayFactor);
    vec3 finalLight = naturalLight + ambientLight + torchColor;
    color.rgb *= finalLight;
    gl_FragData[0] = color;
}
