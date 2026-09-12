#version 130

#include "/settings.glsl"

uniform sampler2D colortex0;
uniform float viewWidth;
uniform float viewHeight;

uniform float frameTimeCounter;

in vec2 texcoord;

const float edgeThresholdMin = 0.03125;
const float edgeThresholdMax = 0.125;
const float subpixelQuality = 0.75;
const int iterations = 12;
const float quality[12] = float[12] (1.0, 1.0, 1.0, 1.0, 1.0, 1.5, 2.0, 2.0, 2.0, 2.0, 4.0, 8.0);

float GetLuminance(vec3 color)
{
    return dot(color, vec3(0.299, 0.587, 0.114));
}

void FXAA311(inout vec3 color)
{
    vec2 view = 1.0 / vec2(viewWidth, viewHeight);
	
    float lumaCenter = GetLuminance(color);
	ivec2 texelCoord = ivec2(gl_FragCoord.xy);

    float lumaDown  = GetLuminance(texelFetch(colortex0, texelCoord + ivec2( 0, -1), 0).rgb);
    float lumaUp    = GetLuminance(texelFetch(colortex0, texelCoord + ivec2( 0,  1), 0).rgb);
    float lumaLeft  = GetLuminance(texelFetch(colortex0, texelCoord + ivec2(-1,  0), 0).rgb);
    float lumaRight = GetLuminance(texelFetch(colortex0, texelCoord + ivec2( 1,  0), 0).rgb);

    float lumaMin = min(lumaCenter, min(min(lumaDown, lumaUp), min(lumaLeft, lumaRight)));
    float lumaMax = max(lumaCenter, max(max(lumaDown, lumaUp), max(lumaLeft, lumaRight)));
    float lumaRange = lumaMax - lumaMin;

    if (lumaRange > max(edgeThresholdMin, lumaMax * edgeThresholdMax))
	{
        float lumaDownLeft  = GetLuminance(texelFetch(colortex0, texelCoord + ivec2(-1, -1), 0).rgb);
        float lumaUpRight   = GetLuminance(texelFetch(colortex0, texelCoord + ivec2( 1,  1), 0).rgb);
        float lumaUpLeft    = GetLuminance(texelFetch(colortex0, texelCoord + ivec2(-1,  1), 0).rgb);
        float lumaDownRight = GetLuminance(texelFetch(colortex0, texelCoord + ivec2( 1, -1), 0).rgb);

        float lumaDownUp    = lumaDown + lumaUp;
        float lumaLeftRight = lumaLeft + lumaRight;

        float lumaLeftCorners  = lumaDownLeft  + lumaUpLeft;
        float lumaDownCorners  = lumaDownLeft  + lumaDownRight;
        float lumaRightCorners = lumaDownRight + lumaUpRight;
        float lumaUpCorners    = lumaUpRight   + lumaUpLeft;

        float edgeHorizontal = abs(-2.0 * lumaLeft   + lumaLeftCorners ) +
                               abs(-2.0 * lumaCenter + lumaDownUp      ) * 2.0 +
                               abs(-2.0 * lumaRight  + lumaRightCorners);
        float edgeVertical   = abs(-2.0 * lumaUp     + lumaUpCorners   ) +
                               abs(-2.0 * lumaCenter + lumaLeftRight   ) * 2.0 +
                               abs(-2.0 * lumaDown   + lumaDownCorners );

        bool isHorizontal = (edgeHorizontal >= edgeVertical);

        float luma1 = isHorizontal ? lumaDown : lumaLeft;
        float luma2 = isHorizontal ? lumaUp : lumaRight;
        float gradient1 = luma1 - lumaCenter;
        float gradient2 = luma2 - lumaCenter;

        bool is1Steepest = abs(gradient1) >= abs(gradient2);
        float gradientScaled = 0.25 * max(abs(gradient1), abs(gradient2));

        float stepLength = isHorizontal ? view.y : view.x;

        float lumaLocalAverage = 0.0;

        if (is1Steepest)
		{
            stepLength = - stepLength;
            lumaLocalAverage = 0.5 * (luma1 + lumaCenter);
        }
		else
		{
            lumaLocalAverage = 0.5 * (luma2 + lumaCenter);
        }

        vec2 currentUv = texcoord;
        if (isHorizontal)
		{
            currentUv.y += stepLength * 0.5;
        }
		else
		{
            currentUv.x += stepLength * 0.5;
        }

        vec2 offset = isHorizontal ? vec2(view.x, 0.0) : vec2(0.0, view.y);

        vec2 uv1 = currentUv - offset;
        vec2 uv2 = currentUv + offset;

        float lumaEnd1 = GetLuminance(texture2D(colortex0, uv1).rgb);
        float lumaEnd2 = GetLuminance(texture2D(colortex0, uv2).rgb);
			
        lumaEnd1 -= lumaLocalAverage;
        lumaEnd2 -= lumaLocalAverage;

        bool reached1 = abs(lumaEnd1) >= gradientScaled;
        bool reached2 = abs(lumaEnd2) >= gradientScaled;
        bool reachedBoth = reached1 && reached2;

        if (!reached1)
		{
            uv1 -= offset;
        }
        if (!reached2)
		{
            uv2 += offset;
        }

        if (!reachedBoth)
		{
            for (int i = 2; i < iterations; i++)
			{
                if (!reached1)
				{
                    lumaEnd1 = GetLuminance(texture2D(colortex0, uv1).rgb);
                    lumaEnd1 = lumaEnd1 - lumaLocalAverage;
                }
                if (!reached2)
				{
				    lumaEnd2 = GetLuminance(texture2D(colortex0, uv2).rgb);
                    lumaEnd2 = lumaEnd2 - lumaLocalAverage;
                }

                reached1 = abs(lumaEnd1) >= gradientScaled;
                reached2 = abs(lumaEnd2) >= gradientScaled;
                reachedBoth = reached1 && reached2;

                if (!reached1)
				{
                    uv1 -= offset * quality[i];
                }
                if (!reached2)
				{
                    uv2 += offset * quality[i];
                }

                if (reachedBoth) break;
            }
        }

        float distance1 = isHorizontal ? (texcoord.x - uv1.x) : (texcoord.y - uv1.y);
        float distance2 = isHorizontal ? (uv2.x - texcoord.x) : (uv2.y - texcoord.y);

        bool isDirection1 = distance1 < distance2;
        float distanceFinal = min(distance1, distance2);

        float edgeThickness = (distance1 + distance2);

        float pixelOffset = - distanceFinal / edgeThickness + 0.5;

        bool isLumaCenterSmaller = lumaCenter < lumaLocalAverage;

        bool correctVariation = ((isDirection1 ? lumaEnd1 : lumaEnd2) < 0.0) != isLumaCenterSmaller;

        float finalOffset = correctVariation ? pixelOffset : 0.0;

        float lumaAverage = (1.0 / 12.0) * (2.0 * (lumaDownUp + lumaLeftRight) + lumaLeftCorners + lumaRightCorners);
        float subPixelOffset1 = clamp(abs(lumaAverage - lumaCenter) / lumaRange, 0.0, 1.0);
        float subPixelOffset2 = (-2.0 * subPixelOffset1 + 3.0) * subPixelOffset1 * subPixelOffset1;
        float subPixelOffsetFinal = subPixelOffset2 * subPixelOffset2 * subpixelQuality;

        finalOffset = max(finalOffset, subPixelOffsetFinal);

        vec2 finalUv = texcoord;

        // Compute the final UV coordinates.
        if (isHorizontal) {
            finalUv.y += finalOffset * stepLength;
        } else {
            finalUv.x += finalOffset * stepLength;
        }

        color = texture2D(colortex0, finalUv).rgb;
    }
}

//vec3 color2 = vec3(0.384, 0.82, 0.914);
//vec3 color3 = vec3(1, 0.275, 0.58);
//vec3 color1 = vec3(0.204, 0.247, 0.239); //самый тёмный

vec3 color2 = vec3(0.333, 0.341, 1);
vec3 color3 = vec3(0.325, 0.345, 1);
vec3 color1 = vec3(0.133, 0.016, 0.325); //самый тёмный

float pos1 = 0;
float pos2 = 0.5;
float pos3 = 1;

float getLuminance(vec3 color) {
    return dot(color, vec3(0.299, 0.587, 0.114));
}

vec3 applyGradient(float gray) {
    if (gray <= pos1) {
        return color1;
    }
    else if (gray <= pos2) {
        float t = (gray - pos1) / (pos2 - pos1);
        return mix(color1, color2, t);
    }
    else if (gray <= pos3) {
        float t = (gray - pos2) / (pos3 - pos2);
        return mix(color2, color3, t);
    }
    else {
        return color3;
    }
}

vec3 colorGrade(vec3 c) {
    // hyperpop градиент
    vec3 low = vec3(0.8, 0.3, 1.0);   // розово-фиолетовый
    vec3 mid = vec3(0.2, 0.9, 1.0);   // голубой
    vec3 high = vec3(1.0, 0.9, 0.6);  // лимонный
    float l = dot(c, vec3(0.299, 0.587, 0.114));
    if (l < 0.4) return mix(low, mid, smoothstep(0.0,0.4,l));
    return mix(mid, high, smoothstep(0.4,1.0,l));
}

void main() {
    vec3 color = texture(colortex0, texcoord).rgb;



    #if TYPE_AA == 0
    FXAA311(color);
    #endif

    vec3 north = texture2D(colortex0, texcoord + vec2(0.0, 1.0 / viewHeight)).rgb;
    vec3 south = texture2D(colortex0, texcoord - vec2(0.0, 1.0 / viewHeight)).rgb;
    vec3 east  = texture2D(colortex0, texcoord + vec2(1.0 / viewWidth, 0.0)).rgb;
    vec3 west  = texture2D(colortex0, texcoord - vec2(1.0 / viewWidth, 0.0)).rgb;

    vec3 blur = (north + south + east + west + color) * 0.2; 
    float strength = 0.85;
    color = color + strength * (color - blur);
	
	float luminance = getLuminance(color.rgb);
	vec3 gradientColor = applyGradient(luminance);
	vec3 finalColor = mix(color.rgb, gradientColor, 0);
	
	finalColor = pow(finalColor, vec3(0.9)); // Снижение контраста
	
	/*DRAWBUFFERS:0*/
	gl_FragData[0].rgb = vec3(finalColor);
}
