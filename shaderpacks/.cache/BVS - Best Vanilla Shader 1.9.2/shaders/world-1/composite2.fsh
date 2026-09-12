#version 130

//Shader by LoLip_p

#include "/settings.glsl"
#include "/lib/util/dither.glsl"

varying vec2 TexCoords;

uniform float viewWidth, viewHeight;
uniform vec3 cameraPosition, previousCameraPosition;
uniform mat4 gbufferPreviousProjection, gbufferProjectionInverse;
uniform mat4 gbufferPreviousModelView, gbufferModelViewInverse;
uniform sampler2D colortex0;
uniform sampler2D depthtex1;

vec3 MotionBlur(vec3 color, float z, float dither)
{
        if (z > 0.56)
		{
            float mbwg = 0.0;
            vec2 doublePixel = 2.0 / vec2(viewWidth, viewHeight);
            vec3 mblur = vec3(0.0);

            vec4 currentPosition = vec4(TexCoords, z, 1.0) * 2.0 - 1.0;

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

            vec2 coord = TexCoords - velocity * (3.5 + dither);

            for (int i = 0; i < 9; i++, coord += velocity) {
                vec2 coordb = clamp(coord, doublePixel, 1.0 - doublePixel);
                mblur += texture2DLod(colortex0, coordb, 0).rgb;
                mbwg += 1.0;
            }
            mblur /= mbwg;
            return mblur;
        } else return color;
}

void main() {
	vec3 color = texture2D(colortex0, TexCoords).rgb;
	
	#if MOTION_BLUR == 1
    float z = texture2D(depthtex1, TexCoords).x;
    float dither = Bayer64(gl_FragCoord.xy);
    color = MotionBlur(color, z, dither);
	#endif
	
	/*DRAWBUFFERS:0*/
	gl_FragData[0] = vec4(color, 1.0);
}
