
#ifdef FRAGMENT_STAGE

uniform sampler2D   texture;

uniform float       blindness;
uniform int         isEyeInWater;

varying vec4        color;
varying vec2        coord0;

void main() {
    
    vec3 light      = vec3(1.0 - blindness);
    vec4 col        = color * vec4(light, 1.0) * texture2D(texture, coord0);

    float fog       = (isEyeInWater>0) ? 1.0 - exp(-gl_FogFragCoord * gl_Fog.density):
    clamp             ((gl_FogFragCoord - gl_Fog.start) * gl_Fog.scale, 0.0, 1.0);

    col.rgb         = mix(col.rgb, gl_Fog.color.rgb, fog);

    gl_FragData[0]  = col;
}

#endif

#ifdef VERTEX_STAGE

uniform mat4        gbufferModelView;
uniform mat4        gbufferModelViewInverse;

varying vec4        color;
varying vec2        coord0;

void main() {

    vec3 pos        = (gl_ModelViewMatrix * gl_Vertex).xyz;
    pos             = (gbufferModelViewInverse * vec4(pos, 1.0)).xyz;

    gl_Position     = gl_ProjectionMatrix * gbufferModelView * vec4(pos, 1.0);
    gl_FogFragCoord = length(pos);

    color           = gl_Color;
    coord0          = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    
}

#endif