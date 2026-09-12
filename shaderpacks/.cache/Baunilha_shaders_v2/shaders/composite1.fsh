#version 430 compatibility
// Vanilla Shader - Iris Version by racxusdev - racxudev.blogspot.com
uniform sampler2D colortex0;
uniform sampler2D depthtex0;
uniform float far;
uniform vec3 fogColor;
uniform vec3 sunPosition;
uniform int isEyeInWater;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjectionInverse;
uniform float viewWidth;
uniform float viewHeight;
in vec2 texcoord;
#include "/lib/settings.glsl"
vec3 projectAndDivide(mat4 projectionMatrix, vec3 position){
  vec4 homPos = projectionMatrix * vec4(position, 1.0);
  return homPos.xyz / homPos.w;
}
/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;
void main() {
	color = texture(colortex0, texcoord);
	float depth = texture(depthtex0, texcoord).r;
	if(depth == 1.0){
		return;
	}
  vec3 sunVec = normalize(sunPosition);
  vec3 worldSunVec = mat3(gbufferModelViewInverse) * sunVec;
  float nightFactor = clamp(-worldSunVec.y, 0.0, 1.0);
  float density = mix(FOG_DENSITY, FOG_DENSITY_NIGHT, nightFactor);
  vec3 NDCPos = vec3(texcoord.xy, depth) * 2.0 - 1.0;
	vec3 viewPos = projectAndDivide(gbufferProjectionInverse, NDCPos);
  float dist = length(viewPos) / far;

  // Desaturação diurna progressiva
  float dayFactor = 1.0 - nightFactor;
  // [DESATIVADO] float dayDesat = dist * 0.05 * dayFactor;
  // [DESATIVADO] color.rgb = mix(color.rgb, vec3(dot(color.rgb, vec3(0.2126, 0.7152, 0.0722))), dayDesat);

  // Névoa diurna suave (haze atmosférico)
  float dayFog = 1.0 - exp(-dist * 0.3);
  vec3 dayFogColor = vec3(0.45, 0.65, 0.9);
  color.rgb = mix(color.rgb, pow(dayFogColor, vec3(2.2)), dayFog * 0.2 * dayFactor);

  // Névoa noturna anti-color-crushing
  float nightFog = 1.0 - exp(-dist * density);
  float nightFogAmount = nightFog * nightFactor;
  vec3 nightFogColor = vec3(0.015, 0.015, 0.04);
  color.rgb = mix(color.rgb, vec3(dot(color.rgb, vec3(0.2126, 0.7152, 0.0722))), nightFogAmount * 0.5);
  color.rgb = mix(color.rgb, nightFogColor, nightFogAmount * 0.8);
  if (isEyeInWater == 1) {
    float waterFogFactor = 1.0 - exp(-dist * WATER_FOG_DENSITY);
    vec3 waterFogColor = vec3(0.02, 0.06, 0.1);
    color.rgb = mix(color.rgb, waterFogColor, clamp(waterFogFactor, 0.0, 0.95));
  }
}
