
#include "/lib/brdf/fresnel.glsl"
#include "/lib/brdf/material.glsl"
#include "/lib/brdf/specular.glsl"

/*
    These two functions used for rough reflections are based on zombye's spectrum shaders
    https://github.com/zombye/spectrum
*/

mat3 getRotationMat(vec3 x, vec3 y) {
	float cosine = dot(x, y);
	vec3 axis = cross(y, x);

	float tmp = 1.0 / dot(axis, axis);
	      tmp = tmp - tmp * cosine;
	vec3 tmpv = axis * tmp;

	return mat3(
		axis.x * tmpv.x + cosine, axis.x * tmpv.y - axis.z, axis.x * tmpv.z + axis.y,
		axis.y * tmpv.x + axis.z, axis.y * tmpv.y + cosine, axis.y * tmpv.z - axis.x,
		axis.z * tmpv.x - axis.y, axis.z * tmpv.y + axis.x, axis.z * tmpv.z + cosine
	);
}
vec3 ggxFacetDist(vec3 viewDir, float roughness, vec2 xy) {
	/*
        GGX VNDF sampling
        http://www.jcgt.org/published/0007/04/01/
    */
    roughness   = max(roughness, 0.001);
    xy.x        = clamp(xy.x * rpi, 0.001, rpi);

    viewDir     = normalize(vec3(roughness * viewDir.xy, viewDir.z));

    float clsq  = dot(viewDir.xy, viewDir.xy);
    vec3 T1     = vec3(clsq > 0.0 ? vec2(-viewDir.y, viewDir.x) * inversesqrt(clsq) : vec2(1.0, 0.0), 0.0);
    vec3 T2     = vec3(-T1.y * viewDir.z, viewDir.z * T1.x, viewDir.x * T1.y - T1.x * viewDir.y);

	float r     = sqrt(xy.x);
	float phi   = tau * xy.y;
	float t1    = r * cos(phi);
	float a     = saturate(1.0 - t1 * t1);
	float t2    = mix(sqrt(a), r * sin(phi), 0.5 + 0.5 * viewDir.z);

	vec3 normalH = t1 * T1 + t2 * T2 + sqrt(saturate(a - t2 * t2)) * viewDir;

	return normalize(vec3(roughness * normalH.xy, normalH.z));
}
vec3 screenspaceRT(vec3 position, vec3 direction, float noise) {
    const uint maxSteps     = 16;

  	float rayLength = ((position.z + direction.z * far * sqrt3) > -near) ?
                      (-near - position.z) / direction.z : far * sqrt3;

    vec3 screenPosition     = viewToScreenSpace(position);
    vec3 endPosition        = position + direction * rayLength;
    vec3 endScreenPosition  = viewToScreenSpace(endPosition);

    vec3 screenDirection    = normalize(endScreenPosition - screenPosition);
        screenDirection.xy  = normalize(screenDirection.xy);

    vec3 maxLength          = (step(0.0, screenDirection) - screenPosition) / screenDirection;
    float stepMult          = minOf(maxLength);
    vec3 screenVector       = screenDirection * stepMult / float(maxSteps);

    vec3 screenPos          = screenPosition + screenDirection * maxOf(pixelSize * pi);

    if (saturate(screenPos.xy) == screenPos.xy) {
        float depthSample   = texelFetch(depthtex0, ivec2(screenPos.xy * viewSize * ResolutionScale), 0).x;
        float linearSample  = depthLinear(depthSample);
        float currentDepth  = depthLinear(screenPos.z);

        if (linearSample < currentDepth) {
            float dist      = abs(linearSample - currentDepth) / currentDepth;
            if (dist <= 0.25) return vec3(screenPos.xy, depthSample);
        }
    }

        screenPos          += screenVector * noise;

    for (uint i = 0; i < maxSteps; ++i) {
        if (saturate(screenPos.xy) != screenPos.xy) break;

        float depthSample   = texelFetch(depthtex0, ivec2(screenPos.xy * viewSize * ResolutionScale), 0).x;
        float linearSample  = depthLinear(depthSample);
        float currentDepth  = depthLinear(screenPos.z);

        if (linearSample < currentDepth) {
            float dist      = abs(linearSample - currentDepth) / currentDepth;
            if (dist <= 0.5) return vec3(screenPos.xy, depthSample);
        }

        screenPos      += screenVector;
    }

    return vec3(1.1);
}

vec3 screenspaceRT_LR(vec3 position, vec3 direction, float noise) {
    const uint maxSteps     = 8;

  	float rayLength = ((position.z + direction.z * far * sqrt3) > -near) ?
                      (-near - position.z) / direction.z : far * sqrt3;

    vec3 screenPosition     = viewToScreenSpace(position);
    vec3 endPosition        = position + direction * rayLength;
    vec3 endScreenPosition  = viewToScreenSpace(endPosition);

    vec3 screenDirection    = normalize(endScreenPosition - screenPosition);
        screenDirection.xy  = normalize(screenDirection.xy);

    vec3 maxLength          = (step(0.0, screenDirection) - screenPosition) / screenDirection;
    float stepMult          = min(minOf(maxLength), 0.5);
    vec3 screenVector       = screenDirection * stepMult / float(maxSteps);

    vec3 screenPos          = screenPosition;

        screenPos          += screenVector * noise;

    for (uint i = 0; i < maxSteps; ++i) {
        if (saturate(screenPos.xy) != screenPos.xy) break;

        float depthSample   = texelFetch(depthtex0, ivec2(screenPos.xy * viewSize * ResolutionScale), 0).x;
        float linearSample  = depthLinear(depthSample);
        float currentDepth  = depthLinear(screenPos.z);

        if (linearSample < currentDepth) {
            float dist      = abs(linearSample - currentDepth) / currentDepth;
            if (dist <= 0.5) return vec3(screenPos.xy, depthSample);
        }

        screenPos      += screenVector;
    }

    return vec3(1.1);
}

#include "/lib/frag/capture.glsl"

vec4 readSkyCapture(vec3 direction, float occlusion) {
    return vec4(texture(colortex4, projectSky(direction, 1)).rgb, occlusion * sqr(saturate(direction.y + 1.0)));
}

void applySkyCapture(inout vec4 color, vec3 sky, float occlusion) {
    #ifdef NOSKY
        if (color.a < 1.0) {
            color = vec4(color.rgb, 1.0);
        } else {
            color = vec4(0);
        }
        return;
    #else
        if (color.a < 1.0) {
            color = vec4(color.rgb, 1.0);
        } else {
            color = vec4(sky * occlusion, occlusion);
        }
        return;
    #endif
}

vec4 readSpherePositionAware(float occlusion, vec3 scenePosition, vec3 direction) {

    #ifdef reflectionCaptureEnabled
        vec2 uv         = unprojectSphere(direction);
        vec3 sampleScenePos = texelFetch(colortex11, ivec2(uv * vec2(1024, 512)), 0).rgb;
        vec3 sceneDir   = normalize(scenePosition);
        float dir       = dot(sceneDir, direction);

        vec3 skyCapture     = texture(colortex4, projectSky(direction, 1)).rgb;

        if (length(sampleScenePos) < length(scenePosition) && dir > 0.0) {
            return vec4(skyCapture * occlusion, occlusion);
        }

        vec2 pos        = uv * vec2(1024.0, 512.0) - 0.5;
        ivec2 location  = ivec2(pos);

        vec2 weights    = fract(pos);

        vec4 s0         = texelFetch(colortex10, location, 0); applySkyCapture(s0, skyCapture, occlusion);
        vec4 s1         = texelFetch(colortex10, (location + ivec2(1, 0)) & ivec2(1023, 511), 0);  applySkyCapture(s1, skyCapture, occlusion);
        vec4 s2         = texelFetch(colortex10, (location + ivec2(0, 1)) & ivec2(1023, 511), 0);  applySkyCapture(s2, skyCapture, occlusion);
        vec4 s3         = texelFetch(colortex10, (location + ivec2(1, 1)) & ivec2(1023, 511), 0);  applySkyCapture(s3, skyCapture, occlusion);

        return mix(mix(s0, s1, weights.x),
                mix(s2, s3, weights.x),
                weights.y);
    #else
        #ifdef NOSKY
        return vec4(0);
        #else
        return vec4(texture(colortex4, projectSky(direction, 1)).rgb * sqrt(occlusion), occlusion);
        #endif
    #endif
}

mat2x3 unpackReflectionAux(vec4 data){
    vec3 shadows    = decodeRGBE8(vec4(unpack2x8(data.x), unpack2x8(data.y)));
    vec3 albedo     = decodeRGBE8(vec4(unpack2x8(data.z), unpack2x8(data.w)));

    return mat2x3(shadows, albedo);
}