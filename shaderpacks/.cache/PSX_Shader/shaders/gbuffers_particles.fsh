#version 460 compatibility
#include "/settings.glsl"

//Diffuse (color) texture.
uniform sampler2D texture;

//0-1 amount of blindness.
uniform float blindness;
//0 = default, 1 = water, 2 = lava.
uniform int isEyeInWater;

//Fog mode
uniform int fogMode;
const int GL_LINEAR = 9729;
const int GL_EXP = 2048;

//Vertex color.
in vec4 color;
//Diffuse texture coordinates.
in vec2 coord0;

void main()
{
    //Visibility amount.
    vec3 light = vec3(1.-blindness);
    
    //Sample texture times Visibility.
    vec4 col = color * vec4(light,1) * texture2D(texture,coord0);

    float fog;
    if(fogMode == GL_LINEAR){
        fog = clamp((gl_FogFragCoord-gl_Fog.start) * gl_Fog.scale, 0., 1.);		
    } else if(fogMode == GL_EXP || isEyeInWater >= 1){
        fog = 1.-clamp(exp(-gl_FogFragCoord * gl_Fog.density), 0., 1.);
    }

    col.rgb = mix(col.rgb, gl_Fog.color.rgb, fog);
    
    //Output the result.
    gl_FragData[0] = col;
}
