#ifndef ATMOSPHERE_GLSL
#define ATMOSPHERE_GLSL

#include "/lib/common.glsl"

// Lo declara ESTE include: no lo redeclares en programas que lo incluyan.
uniform float rainStrength;

/* Color base del cielo (día/noche) según la dirección. Lo usan el cielo
   (deferred.fsh) Y la niebla/SSR (composite.fsh) => horizonte sin costura.
   v1.1: al llover el cielo se vuelve gris y apagado; como la niebla y los
   reflejos usan esta misma función, TODO el ambiente encapota a la vez. */
vec3 atmosphere(vec3 dir, float dayFactor) {
    float y = clamp(dir.y, 0.0, 1.0);
    vec3 nHor = vec3(0.020, 0.040, 0.078);   // horizonte noche
    vec3 nZen = vec3(0.004, 0.010, 0.030);   // cenit noche
    vec3 night = mix(nHor, nZen, pow(y, 0.45));
    vec3 dHor = vec3(0.52, 0.66, 0.84);      // horizonte día
    vec3 dZen = vec3(0.16, 0.36, 0.72);      // cenit día
    vec3 day  = mix(dHor, dZen, pow(y, 0.55));
    vec3 col  = mix(night, day, dayFactor);

    float lum = dot(col, vec3(0.30, 0.55, 0.15));
    col = mix(col, vec3(lum) * vec3(0.85, 0.90, 1.00), rainStrength * 0.65);
    col *= 1.0 - 0.25 * rainStrength;
    return col;
}

#endif
