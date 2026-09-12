#version 130 compatibility

uniform sampler2D texture;
uniform sampler2D depthtex0;
uniform sampler2D noisetex;
uniform vec3 cameraPosition;
uniform vec4 entityColor;
uniform float viewWidth, viewHeight;
uniform float dhNearPlane;
uniform float dhFarPlane;

uniform vec3 fogColor;

in vec4 color;
in vec3 playerPos;
in vec2 texcoord;
in vec3 viewSpaceGeoNormal;

float Noise3D(vec3 p) {
    p.z = fract(p.z) * 32.0;
    float iz = floor(p.z);
    float fz = fract(p.z);
    vec2 a_off = vec2(23.0, 29.0) * (iz) / 128.0;
    vec2 b_off = vec2(23.0, 29.0) * (iz + 1.0) / 128.0;
    float a = texture2D(noisetex, p.xy + a_off).r;
    float b = texture2D(noisetex, p.xy + b_off).r;
    return mix(a, b, fz);
}

float max0(float x) {
    return max(x, 0.0);
}

void main() {
	vec4 albedo = texture2D(texture, texcoord) * color;
	float depth = texture2D(depthtex0, gl_FragCoord.xy / vec2(viewWidth, viewHeight)).r;
	
	if(length(viewSpaceGeoNormal * 0.5 + 0.5) != 0.0f) {
		//albedo.a = 0.75;
	}
	
	if(depth != 1.0) {
		discard;
	}
	
	vec3 noisePos = floor((playerPos + cameraPosition) * 4.0 + 0.001) / 32.0;
    float noiseTexture = Noise3D(noisePos) + 0.5;
    float noiseFactor = max0(1.0 - 0.3 * dot(albedo.rgb, albedo.rgb));
    albedo.rgb *= pow(noiseTexture, 0.35 * noiseFactor);
	
	float distFromCamera = distance(vec3(0), playerPos);
	float fogBlendValue = clamp((distFromCamera - dhNearPlane) / (dhFarPlane - dhNearPlane), 0, 1);
	albedo.rgb = mix(albedo.rgb, fogColor, fogBlendValue);
	
	/*DRAWBUFFERS:02*/
	gl_FragData[0] = albedo;
	gl_FragData[1].rgb = viewSpaceGeoNormal * 0.5 + 0.5;
}
