#version 460 compatibility
#include "/settings.glsl"
#include "/utility.glsl"
#include "/lib/noise/classicnoise3D.glsl"

//Texture atlas size.
uniform ivec2 atlasSize;
//Diffuse (color) texture.
uniform sampler2D texture;
//Lighting from day/night + shadows + light sources.
uniform sampler2D lightmap;

uniform vec3 cameraPosition;

uniform float frameTimeCounter;

//Fog mode
uniform int fogMode;
const int GL_LINEAR = 9729;
const int GL_EXP = 2048;

//0 = default, 1 = water, 2 = lava.
uniform int isEyeInWater;

//Color and Light.
in vec4 color;
in float light;
in float dist_xz;

in vec2 coord0;

in vec3 vertex_coord0;

in vec2 coord1;

void main()
{

    vec4 albedo = texture2D(texture, coord0);

    vec3 noise_coord = (vertex_coord0 + cameraPosition) * 16;
    noise_coord = round(noise_coord);
    noise_coord /= 16;

    noise_coord += sin(frameTimeCounter / 3600) * 1024;

    float noise = 0;
    noise += pnoise(noise_coord * 0.1, vec3(256));
    noise += pnoise(noise_coord * 1, vec3(256));
    noise += pnoise(noise_coord * 10, vec3(256));
    noise /= 3;
    noise = (noise + 1) / 2;
    albedo.rgb *= vec3(noise + 0.5);
    albedo.a *= noise + 0.5;

    albedo.rgb *= color.rgb * light;
    albedo.rgb *= texture2D(lightmap, coord1).rgb;

    float fog;
    if(fogMode == GL_LINEAR){
        fog = clamp((gl_FogFragCoord-gl_Fog.start) * gl_Fog.scale, 0., 1.);		
    } else if(fogMode == GL_EXP || isEyeInWater >= 1){
        fog = 1.-clamp(exp(-gl_FogFragCoord * gl_Fog.density), 0., 1.);
    }

    albedo.rgb = mix(albedo.rgb, gl_Fog.color.rgb, fog);

    albedo.rgb = floor(albedo.rgb * 16);
    albedo.rgb /= 16;

    if (dist_xz > 0.975){
        discard;
    }

    gl_FragData[0] = albedo;
}
