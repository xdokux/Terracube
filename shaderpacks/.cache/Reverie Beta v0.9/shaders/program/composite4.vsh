#include "/lib/all_the_libs.glsl"

#include "/generic/clouds.glsl"
out vec2 texcoord;

flat out vec3 LightPosFlare;

flat out vec3 LightColorDirect;

void main() {
	gl_Position = ftransform();
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	LightColorDirect = get_shadowlight_color();

	LightPosFlare = view_screen(shadowLightPosition, false, false);

	// Lens flare
	if(LightPosFlare.z <= 1) {
		bool _void;
		float IsSunVisible = float(get_depth_solid(LightPosFlare.xy, _void) >= 1);

		IsSunVisible *= float(all(lessThan(LightPosFlare.xy, vec2(1))));
		IsSunVisible *= float(all(greaterThan(LightPosFlare.xy, vec2(0))));

		#ifdef CLOUDS
			float _Void;
			IsSunVisible *= get_clouds(vec3(1000), view_player(sLightPosN, false), 6, cameraPosition, false, vec2(0), 1, _Void).a;
		#endif
		IsSunVisible *= 1 - float(isEyeInWater == 1) * 0.97;
		
		dataBuf.SunVisibility = mix(dataBuf.SunVisibility, IsSunVisible, min(1, 10*frameTime));
	}
	else {
		dataBuf.SunVisibility = 0;
	}

	LightPosFlare.xy -= 0.5;
}
