
#ifdef FRAGMENT_STAGE

uniform sampler2D   texture;
uniform sampler2D   lightmap;

uniform vec4        entityColor;
uniform float       blindness;
uniform int         isEyeInWater;

varying vec4        color;

varying vec2        coord0;
varying vec2        coord1;

void main() {

    vec3 light      = (0.85 - blindness) * texture2D(lightmap, coord1).rgb;
    vec4 col        = color * vec4(light, 1.0) * texture2D(texture, coord0);
    #ifdef MOB_FLASH
    col.rgb         = mix(col.rgb, entityColor.rgb, entityColor.a);
    #endif

    #ifdef FOG
    float fog       = (isEyeInWater==0.9) ? 1.0 - exp(-gl_FogFragCoord * gl_Fog.density):
    clamp           ((gl_FogFragCoord - gl_Fog.start * FOG_DIST) * gl_Fog.scale, 0.0, 1.0);
    #endif

    #ifdef FOG
    col.rgb         = mix(col.rgb, gl_Fog.color.rgb, fog * FOG_DENSITY);
    #else
    col.rgb         = col.rgb;
    #endif

    gl_FragData[0]  = col;
}

#endif



#ifdef VERTEX_STAGE

attribute float     mc_Entity;

uniform mat4        gbufferModelView;
uniform mat4        gbufferModelViewInverse;

varying vec4        color;
varying vec2        coord0;
varying vec2        coord1;

void main() {

    vec3 pos        = (gl_ModelViewMatrix * gl_Vertex).xyz;
    pos             = (gbufferModelViewInverse * vec4(pos, 1.0)).xyz;

    gl_Position     = gl_ProjectionMatrix * gbufferModelView * vec4(pos, 1.0);
    gl_FogFragCoord = length(pos);

    vec3 normal     = gl_NormalMatrix * gl_Normal;
    normal          = (mc_Entity == 1) ? vec3(0, 1, 0) : (gbufferModelViewInverse * vec4(normal, 0)).xyz;

    float light = 0.8 - 0.25 * abs(normal.x * 0.9 + normal.z * 0.3) + normal.y * 0.2;

    color = vec4(gl_Color.rgb * light, gl_Color.a);

    coord0 = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    coord1 = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
}

#endif
