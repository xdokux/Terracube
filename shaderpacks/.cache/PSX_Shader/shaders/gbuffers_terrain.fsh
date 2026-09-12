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

//Diffuse and lightmap texture coordinates.
in vec2 coord0;
in vec2 coord0_mid;

in vec3 vertex_coord0;

in vec2 local_coord0;
in vec4 local_coord0_comp;

in vec2 coord1;

void main()
{
    vec2 texcoord = (local_coord0 * local_coord0_comp.zw) + local_coord0_comp.xy;
    vec4 albedo = texture2D(texture, texcoord);

    vec3 sharpen = vec3(0);

    int samples_count = 1;
    float blur_samples_size = 0.15;
    float sharpen_samples_size = blur_samples_size * 2;

    vec2 samples_coord = (local_coord0 * local_coord0_comp.zw) + local_coord0_comp.xy;

    for (int u = -samples_count; u <= samples_count; u++) {
        for (int v = -samples_count; v <= samples_count; v++) {
            vec2 offset = ((vec2(u, v) / samples_count) / 16) * local_coord0_comp.zw;
            vec2 blur_coord = samples_coord;
            blur_coord += offset * blur_samples_size;
            blur_coord = wrapMirror(blur_coord, local_coord0_comp.xy, local_coord0_comp.xy + local_coord0_comp.zw);
            albedo.rgb += texture2D(texture, blur_coord).rgb;

            vec2 sharpen_coord = samples_coord;
            sharpen_coord += offset * sharpen_samples_size;
            sharpen_coord = wrapMirror(sharpen_coord, local_coord0_comp.xy, local_coord0_comp.xy + local_coord0_comp.zw);
            sharpen += texture2D(texture, sharpen_coord).rgb;
        }
    }
    albedo.rgb /= pow(samples_count * 2 + 1, 2);
    sharpen /= pow(samples_count * 2 + 1, 2);
    sharpen -= albedo.rgb;

    sharpen = vec3(sharpen.r + sharpen.g + sharpen.b) / 3;

    albedo.rgb -= sharpen;

    vec3 noise_coord = (vertex_coord0 + cameraPosition) * 16;
    noise_coord = round(noise_coord);
    noise_coord /= 16;

    float noise = 0;
    noise += pnoise(noise_coord * 0.1, vec3(256));
    noise += pnoise(noise_coord * 1, vec3(256));
    noise += pnoise(noise_coord * 10, vec3(256));
    noise /= 3;
    noise = (noise + 1) / 2;
    albedo.rgb *= vec3(noise + 0.5);

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
