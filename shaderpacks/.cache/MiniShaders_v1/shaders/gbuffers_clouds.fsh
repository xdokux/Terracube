#version 120

// GamesofDev is non chalant
varying vec2 texcoord;
varying vec4 glColor;
varying vec3 worldPos;

uniform sampler2D texture;
uniform int worldTime;
uniform vec3 sunPosition;
uniform vec3 skyColor;

/* DRAWBUFFERS:0 */

void main() {
    vec4 cloudTex = texture2D(texture, texcoord) * glColor;
    
    if (cloudTex.a < 0.1) discard;
    
    // Time of day calculation
    float time = mod(float(worldTime), 24000.0);
    float dayFactor = 0.0;
    float sunsetFactor = 0.0;
    
    // Day (0 - 12000)
    if (time < 12000.0) {
        dayFactor = 1.0;
    }
    // Sunset (12000 - 13500)
    else if (time < 13500.0) {
        float t = (time - 12000.0) / 1500.0;
        dayFactor = 1.0 - t;
        sunsetFactor = sin(t * 3.14159);
    }
    // Night (13500 - 22500)
    else if (time < 22500.0) {
        dayFactor = 0.0;
    }
    // Sunrise (22500 - 24000)
    else {
        float t = (time - 22500.0) / 1500.0;
        dayFactor = t;
        sunsetFactor = sin(t * 3.14159);
    }
    
    // === CLOUD COLORS ===
    
    // Day clouds - bright white with slight blue tint
    vec3 dayCloudBright = vec3(1.0, 1.0, 1.0);
    vec3 dayCloudShadow = vec3(0.7, 0.75, 0.85);
    
    // Sunset clouds - warm orange/pink
    vec3 sunsetCloudBright = vec3(1.0, 0.85, 0.7);
    vec3 sunsetCloudShadow = vec3(0.9, 0.5, 0.4);
    
    // Night clouds - dark blue/purple
    vec3 nightCloudBright = vec3(0.15, 0.18, 0.25);
    vec3 nightCloudShadow = vec3(0.08, 0.1, 0.15);
    
    // Blend cloud colors based on time
    vec3 cloudBright = mix(nightCloudBright, dayCloudBright, dayFactor);
    vec3 cloudShadow = mix(nightCloudShadow, dayCloudShadow, dayFactor);
    
    // Add sunset colors
    cloudBright = mix(cloudBright, sunsetCloudBright, sunsetFactor);
    cloudShadow = mix(cloudShadow, sunsetCloudShadow, sunsetFactor);
    
    // Use texture brightness for cloud shading
    float brightness = cloudTex.r;
    vec3 cloudColor = mix(cloudShadow, cloudBright, brightness);
    
    // Sun lighting on clouds
    vec3 sunDir = normalize(sunPosition);
    vec3 viewDir = normalize(-worldPos);
    
    // Simple rim lighting effect
    float rimLight = pow(1.0 - abs(dot(viewDir, vec3(0.0, 1.0, 0.0))), 2.0) * 0.3;
    cloudColor += vec3(1.0, 0.95, 0.85) * rimLight * dayFactor;
    
    // Slightly transparent clouds
    float alpha = cloudTex.a * 0.9;
    
    // Night clouds more transparent
    alpha *= mix(0.6, 1.0, dayFactor);
    
    gl_FragData[0] = vec4(cloudColor, alpha);
}
