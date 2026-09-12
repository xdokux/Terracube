#version 130

#include "/settings.glsl"

in vec2 texcoord;

uniform sampler2D colortex0;
uniform float viewWidth, viewHeight;
vec2 finalUv;

#if MOTION_BLUR == 1
#include "/lib/dither.glsl"
uniform vec3 cameraPosition, previousCameraPosition;
uniform mat4 gbufferPreviousProjection, gbufferProjectionInverse;
uniform mat4 gbufferPreviousModelView, gbufferModelViewInverse;
uniform sampler2D depthtex1;

vec3 MotionBlur(vec3 color, float z, float dither)
{
        if (z > 0.56)
		{
            float mbwg = 0.0;
            vec2 doublePixel = 2.0 / vec2(viewWidth, viewHeight);
            vec3 mblur = vec3(0.0);

            vec4 currentPosition = vec4(texcoord, z, 1.0) * 2.0 - 1.0;

            vec4 viewPos = gbufferProjectionInverse * currentPosition;
            viewPos = gbufferModelViewInverse * viewPos;
            viewPos /= viewPos.w;

            vec3 cameraOffset = cameraPosition - previousCameraPosition;

            vec4 previousPosition = viewPos + vec4(cameraOffset, 0.0);
            previousPosition = gbufferPreviousModelView * previousPosition;
            previousPosition = gbufferPreviousProjection * previousPosition;
            previousPosition /= previousPosition.w;

            vec2 velocity = (currentPosition - previousPosition).xy;
            velocity = velocity / (1.0 + length(velocity)) * MOTION_BLURRING_STRENGTH * 0.02;

            vec2 coord = texcoord - velocity * (3.5 + dither);
			finalUv = coord;

			#if ANTI_ALIASING == 1
			FXAA311(color);
			#endif

            for (int i = 0; i < 9; i++, finalUv += velocity) {
                vec2 coordb = clamp(finalUv, doublePixel, 1.0 - doublePixel);
                mblur += texture2DLod(colortex0, coordb, 0).rgb;
                mbwg += 1.0;
            }
            mblur /= mbwg;
            return mblur;
        } else return color;
}
#endif

void main()
{
    vec3 color = texture(colortex0, texcoord).rgb;
	
	#if MOTION_BLUR == 1
    float z = texture2D(depthtex1, texcoord).x;
    float dither = Bayer64(gl_FragCoord.xy);
    color = MotionBlur(color, z, dither);
	#endif
	
	/*DRAWBUFFERS:0*/
	gl_FragData[0].rgb = vec3(color);
}
