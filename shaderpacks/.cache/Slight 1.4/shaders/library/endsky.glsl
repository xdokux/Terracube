uniform mat4 gbufferModelView;
uniform vec3 sunPosition;

vec3 calculateSkyGradient(vec3 viewDir) {
    float upDot = dot(viewDir, normalize(gbufferModelView[1].xyz));

    float baseT = clamp(upDot * 0.5 + 0.5, 0.0, 1.0);
    vec3 base = mix(vec3(0.025, 0.0, 0.1), vec3(0.0, 0.0, 0.1), baseT);

    float u = (upDot < -0.02) ? 0.0 : max(upDot, 0.0);
    float fogFactor = 0.025 / (u * u + 0.025);

    return mix(base, vec3(0.05, 0.0, 0.1), fogFactor);
}

vec3 calculateMie(vec3 viewDir){
    vec3 sunDir = normalize(sunPosition);

    float mu = abs(dot(viewDir, sunDir));
    float glow = pow(mu, 16.0) * 0.75;
	glow *= 0.2;

    return vec3(1.0, 0.5, 0.5) * glow * 5.0;
}