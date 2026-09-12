const vec3 MOD3 = vec3(.1031,.11369,.13787);
float hash12(vec2 p)
{
	vec3 p3  = fract(vec3(p.xyx) * MOD3);
    p3 += dot(p3, p3.yzx + 19.19);
    return fract((p3.x + p3.y) * p3.z);
}

vec3 getPosition(vec2 uv, mat4 dhProjInv, sampler2D dhDTex1) {
    float z = texture2D(dhDTex1, uv).r;
	vec2 ndc = uv * 2.0 - 1.0;
	vec4 clip = vec4(ndc, z * 2.0 - 1.0, 1.0);
	vec4 view = dhProjInv * clip;
	view /= view.w;
	return view.xyz;
}

vec3 getNormal(vec2 uv, sampler2D ctex2) {
    vec3 n = texture2D(ctex2, uv).xyz * 2.0 - 1.0;
    return normalize(n);
}

float doAO(vec2 uv, vec2 dir, vec3 p, vec3 n, mat4 dhProjInv, sampler2D dhDTex1) {
    vec3 samplePos = getPosition(uv + dir, dhProjInv, dhDTex1) - p;
    float dist = length(samplePos);
    vec3  v    = samplePos / dist;
    float d    = dist * 2.0f;
    float ao = max(dot(n, v), 0.0) / (1.0 + d);
    ao *= smoothstep(10f, 10f * 0.5, dist);
    return ao;
}

float spiralAO(vec2 uv, vec3 p, vec3 n, float rad, mat4 dhProjInv, float fTC, sampler2D dhDTex1) {
    const float golden = 2.4; // ≈ π*(3 - √5)
    float ao = 0.0;
    float inv = 1.0 / float(16);
	float radius = 0.0;
    float phase = hash12((uv + fTC) * 100.0) * 6.28;
    float step = rad * inv;
    for (int i = 0; i < 16; i++) {
        vec2 dir = vec2(sin(phase), cos(phase));
		radius += step;
        phase += golden;
        ao += doAO(uv, dir * radius, p, n, dhProjInv, dhDTex1);
    }
    return ao * inv;
}
