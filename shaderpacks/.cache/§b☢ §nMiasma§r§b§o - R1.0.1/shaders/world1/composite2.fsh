#version 130

uniform sampler2D texture;
uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D depthtex1;

uniform float viewWidth, viewHeight, aspectRatio;

uniform vec3 cameraPosition, previousCameraPosition;

uniform mat4 gbufferPreviousProjection, gbufferProjectionInverse;
uniform mat4 gbufferPreviousModelView, gbufferModelViewInverse;

in vec2 texCoord;

const bool colortex1Clear = false;
/*
const int colortex0Format = RGB8;
const int colortex1Format = RGBA8;
*/

in vec2 texcoord;

vec2 neighbourhoodOffsets[8] = vec2[8](
    vec2(-1.0, -1.0),
    vec2( 0.0, -1.0),
    vec2( 1.0, -1.0),
    vec2(-1.0,  0.0),
    vec2( 1.0,  0.0),
    vec2(-1.0,  1.0),
    vec2( 0.0,  1.0),
    vec2( 1.0,  1.0)
);

vec2 Reprojection(vec3 pos) {
    pos = pos * 2.0 - 1.0;
    vec4 viewPosPrev = gbufferProjectionInverse * vec4(pos, 1.0);
    viewPosPrev /= viewPosPrev.w;
    viewPosPrev = gbufferModelViewInverse * viewPosPrev;

    float useOffset = float(pos.z > 0.56);
    vec3 cameraOffset = (cameraPosition - previousCameraPosition) * useOffset;
    
    vec4 worldPosPrev = viewPosPrev + vec4(cameraOffset, 0.0);
    vec4 previousPosition = gbufferPreviousProjection * gbufferPreviousModelView * worldPosPrev;
    
    float invW = 0.5 / previousPosition.w;
    return previousPosition.xy * invW + 0.5;
}

vec3 NeighbourhoodClamping(vec3 color, vec3 tempColor, vec2 viewInv) {
    vec3 minclr = color;
    vec3 maxclr = color;

    for (int i = 0; i < 8; i++) {
        vec3 clr = texture2D(colortex0, texCoord + neighbourhoodOffsets[i] * viewInv).rgb;
        minclr = min(minclr, clr);
        maxclr = max(maxclr, clr);
    }

    return clamp(tempColor, minclr, maxclr);
}

float exp_approx(float x) {
    return 1.0 / (1.0 + x + 0.5 * x * x);
}

vec4 TemporalAA(inout vec3 color, float tempData) {
    vec3 coord = vec3(texCoord, texture2D(depthtex1, texCoord).r);
    vec2 prvCoord = Reprojection(coord);
    
    vec2 clampedCoord = clamp(prvCoord, 0.0, 1.0);
    vec3 tempColor = texture2D(colortex1, prvCoord).rgb;
    float isValid = float(prvCoord == clampedCoord);

    if (tempColor == vec3(0.0)) return vec4(color, tempData);
    
    vec2 viewInv = vec2(1.0 / viewWidth, 1.0 / viewHeight);
    tempColor = NeighbourhoodClamping(color, tempColor, viewInv);
    
    vec2 velocity = (texCoord - prvCoord) * vec2(viewWidth, viewHeight);
    float blendFactor = isValid * (0.6 * exp_approx(length(velocity)) + 0.3);
    color = mix(color, tempColor, blendFactor);
    return vec4(color, tempData);
}

void main()
{
    vec3 sampledColor = texture2D(colortex0, texCoord).rgb;
    float prevAlpha = texture2D(colortex1, texCoord).a;
	
    float depth = texture2D(depthtex1, texCoord).r;
	
	if(depth == 1.0)
	{
		/*DRAWBUFFERS:01*/
		gl_FragData[0].rgb = sampledColor;
		gl_FragData[1] = vec4(vec3(1), 0);
		return;
	}
	
	vec4 prev = TemporalAA(sampledColor, prevAlpha);
	
    /*DRAWBUFFERS:01*/
    gl_FragData[0].rgb = sampledColor;
    gl_FragData[1] = prev;
}
