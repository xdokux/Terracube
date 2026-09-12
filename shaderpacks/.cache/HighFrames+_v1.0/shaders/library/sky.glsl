uniform mat4 gbufferModelView;
uniform vec3 sunPosition;
uniform float rainStrength;

vec3 calculateSkyGradient(vec3 viewDir) {
    float upDot = dot(viewDir, normalize(gbufferModelView[1].xyz));

    float baseT = clamp(upDot * 0.5 + 0.5, 0.0, 1.0);
    vec3 base = mix(getSkyMiddleColor(), getSkyTopColor(), baseT);

    float u = (upDot < -0.02) ? 0.0 : max(upDot, 0.0);
    float fogFactor = 0.025 / (u * u + 0.025);

    return mix(base, getSkyHorizonColor(), fogFactor);
}

vec3 calculateMie(vec3 viewDir){
    vec3 sunDir = normalize(sunPosition);

    float mu = abs(dot(viewDir, sunDir));
    float glow = pow(mu, mix(16.0, 4.0, rainStrength)) * 0.75 + pow(mu, mix(128.0, 4.0, rainStrength));
	glow *= 0.2;

    return getPointMieColor() * glow * (1.5 - rainStrength);
}