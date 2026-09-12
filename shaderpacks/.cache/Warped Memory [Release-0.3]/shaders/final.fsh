#version 120

// Input data from vertex shader
varying vec2 vTexCoord;
varying vec4 vPosition;

// Textures
uniform sampler2D gtexture;
uniform sampler2D tex;

// Parameters for post-processing
uniform float time;

uniform sampler2D shadowtex0;
varying vec4 shadowPos;

#include settings.glsl


void main()
{
    vec4 color = texture2D(gtexture, vTexCoord);


    // black-gold color palette
    float gray = dot(color.rgb, vec3(0.3, 0.59, 0.11));
    vec3 sepia = vec3(1.2 * gray, 1.0 * gray, 0.8 * gray);
    

    // granularity (noise effect)
    float noise = fract(sin(dot(vTexCoord.xy + time, vec2(12.9898, 78.233))) * 43758.5453) * NOISE;
    sepia += noise * 0.1;


    // smooth shadows
    vec4 shadowColor = vec4(0.2, 0.2, 0.4, 1.0); // Blue shadow
    float shadowFactor = 0.1;
    sepia = mix(sepia, shadowColor.rgb, shadowFactor);


    // **Chromatic Aberration & Double Vision Effect**
    float distortion = sin(vTexCoord.y * 10.0 + time * 2.0) * GLICH; // Ripped distortion //0.01
    vec2 offsetR = vec2(distortion, 0.0);
    vec2 offsetB = vec2(-distortion, 0.0);

    float r = texture2D(gtexture, vTexCoord + offsetR).r;
    float g = texture2D(gtexture, vTexCoord).g;
    float b = texture2D(gtexture, vTexCoord + offsetB).b;

    vec3 chromaticColor = vec3(r, g, b);


    // **Ghost Image (double vision)**
    vec4 ghost = texture2D(gtexture, vTexCoord + vec2(distortion * 2.0, distortion * GIMG));
    chromaticColor = mix(chromaticColor, ghost.rgb, 0.3);

    chromaticColor += noise;


    // Calculation of bloom effect
    vec4 bloom = vec4(0.0);
    vec4 blurColor = vec4(-0.0); //brg
    float intensity = -2.0; //color-
    float radius = 0.1;
    for(int i = -4; i < 4; i++) {
        for(int j = -4; j < 4; j++) {
            vec2 offset = vec2(float(i), float(j)) / 312.0;
            blurColor += texture2D(gtexture, vTexCoord + offset) * BLURCOLOR; //0.006
        }
    }
    bloom = blurColor * intensity;


    // Applying bloom to the main color
    chromaticColor += bloom.rgb;

    vec3 finalColor = mix(sepia, chromaticColor, 0.51);

    gl_FragColor = vec4(finalColor, color.a);
}