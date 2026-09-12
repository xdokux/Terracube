#version 120

//#define CinematicBars
#define Saturation 1.0 //[0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5]
#define Exposure 1.0 //[0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5]

uniform sampler2D gcolor;
varying vec4 texcoord;
uniform float aspectRatio;
#define Bloom
#define BloomQuality 1.0 //[1.0 2.0 3.0 4.0]

float rand(highp vec2 coord){
    return fract(sin(dot(coord.xy ,vec2(12.9898,78.233))) * 43758.5453);
}

vec2 rand2d(highp  vec2 coord)
{
    float x = rand(coord);
    float y = rand(coord * 10000.0);
    return vec2(x, y);
}


vec3 bloom()
{
    float bloomSteps = 4.0;
    float bloomRadius = 0.02;
    float bloomThreshold = 1.0;
    float bloomIntancity = 1.0;

    vec4 bloomTexture = vec4(0.0);

    float totalSteps = 0.0;
    for(float n = 1.0; n <= BloomQuality; n += 1.0)
    {
        for(float i = 1.0; i <= bloomSteps * n; i += 1.0){
            totalSteps += 1.0;
            vec2 stepCoord = vec2(sin(i * 6.0 / bloomSteps), cos(i * 6.0 / bloomSteps)) * bloomRadius * vec2(1.0, aspectRatio) * n;
            vec2 jitterCoord = (rand2d(texcoord.xy) - 0.5) * bloomRadius;
            bloomTexture += texture2D(gcolor, texcoord.xy + stepCoord + jitterCoord);
        }
    }
    bloomTexture /= totalSteps;


    float brightness = (bloomTexture.r + bloomTexture.g + bloomTexture.b) / 3.0;
    brightness = pow(brightness, bloomThreshold);
    bloomTexture *= bloomIntancity * brightness;

    return bloomTexture.rgb;
}

void main() {

    vec3 color = texture2D(gcolor, texcoord.st).rgb;	
    color.r = color.r*1.8;

    #ifdef Bloom
        color.rgb += bloom();
    #endif

    color *= Exposure;

    float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
    color = mix(vec3(luma), color, Saturation);

    #ifdef CinematicBars
        if (texcoord.y < 0.12 || texcoord.y > 0.88) {
            color = vec3(0.0);
        }
    #endif

    gl_FragColor = vec4(color,1.0f);	
}