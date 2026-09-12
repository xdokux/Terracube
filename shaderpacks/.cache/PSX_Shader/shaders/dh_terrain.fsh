#version 460 compatibility

uniform sampler2D depthtex0;

uniform float viewWidth;
uniform float viewHeight;

//Lighting from day/night + shadows + light sources.
uniform sampler2D lightmap;

//0 = default, 1 = water, 2 = lava.
uniform int isEyeInWater;

//Color and Light.
in vec4 color;
in float light;
in float dist_xz;

//Diffuse and lightmap texture coordinates.
in vec2 coord0;
in vec2 coord1;

void main()
{
    vec4 albedo = color * texture2D(lightmap,coord1);

    float fog_intensity = 4;
    if (isEyeInWater > 0){
        fog_intensity = 1;
    }
    float fog = clamp(pow(dist_xz / fog_intensity, 1), 0, 1);
    albedo.rgb = mix(albedo.rgb, gl_Fog.color.rgb, fog);

    vec2 depthCoord = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
    float depth = texture(depthtex0, depthCoord).r;

    if (dist_xz < 0.975 || depth != 1.0){
        discard;
    }

    gl_FragData[0] = pow(albedo, vec4(1.25));
}