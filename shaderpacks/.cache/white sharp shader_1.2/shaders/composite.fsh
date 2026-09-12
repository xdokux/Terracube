#version 300

uniform sampler2D gtexture;
uniform sampler2D lightmap;
uniform float viewHeight;
uniform float viewWidth;
uniform int worldTime;
uniform vec3 worldPos;

layout(location = 0) out vec4 outColor0;

in vec2 texCoord;
in vec3 foliageColor;
in vec2 lightMapCoords;

#define LINE_BRIGHTNESS 1.0 // [0.1 0.2 0.3 0.4 .0.5 0.6 0.7 0.8 0.9 1.0]
#define COLOR_SCHEME 2 // [0 1 2 3]
#define RAINBOW_SPEED 1.0 // [0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0 3.1 3.2 3.3 3.4 3.5 3.6 3.7 3.8 3.9 4.0 4.1 4.2 4.3 4.4 4.5 4.6 4.7 4.8 4.9 5.0 5.1 5.2 5.3 5.4 5.5 5.6 5.7 5.8 5.9 6.0 6.1 6.2 6.3 6.4 6.5 6.6 6.7 6.8 6.9 7.0 7.1 7.2 7.3 7.4 7.5 7.6 7.7 7.8 7.9 8.0 8.1 8.2 8.3 8.4 8.5 8.6 8.7 8.8 8.9 9.0 9.1 9.2 9.3 9.4 9.5 9.6 9.7 9.8 9.9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 69 70 71 72 73 74 75 76 77 78 79 80 81 82 83 84 85 86 87 88 89 90 91 92 93 94 95 96 97 98 99 100]
#define RAINBOW_LINE_SCALE 1.0 // [0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0 3.1 3.2 3.3 3.4 3.5 3.6 3.7 3.8 3.9 4.0 4.1 4.2 4.3 4.4 4.5 4.6 4.7 4.8 4.9 5.0 5.1 5.2 5.3 5.4 5.5 5.6 5.7 5.8 5.9 6.0 6.1 6.2 6.3 6.4 6.5 6.6 6.7 6.8 6.9 7.0 7.1 7.2 7.3 7.4 7.5 7.6 7.7 7.8 7.9 8.0 8.1 8.2 8.3 8.4 8.5 8.6 8.7 8.8 8.9 9.0 9.1 9.2 9.3 9.4 9.5 9.6 9.7 9.8 9.9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 69 70 71 72 73 74 75 76 77 78 79 80 81 82 83 84 85 86 87 88 89 90 91 92 93 94 95 96 97 98 99 100]

vec3 hsv2rgb(vec3 c) {
    vec3 p = abs(fract(c.xxx + vec3(0., 2./3., 1./3.)) * 6. - 3.);
    return c.z * mix(vec3(1.), clamp(p - 1., 0., 1.), c.y);
}

void main() {
    vec2 uv = gl_FragCoord.xy / vec2(viewWidth,viewHeight);

    vec3 currentPixel = texture(gtexture, uv).rgb;
    vec3 rightPixel   = texture(gtexture, uv + vec2(1.0 / viewWidth, 0.0)).rgb;
    vec3 bottomPixel  = texture(gtexture, uv + vec2(0.0, 1.0 / viewHeight)).rgb;

    vec3 colorDifference = abs(currentPixel - rightPixel) + abs(currentPixel - bottomPixel);
    float edge = length(colorDifference) > 0.1 ? 1.0 : 0.0;

    vec3 finalColor;

    switch (COLOR_SCHEME) {
        case 0: // ЧБ
            {
                finalColor = vec3(edge) * LINE_BRIGHTNESS;
            }
            break;
        case 1: // Цвет (ориг. пиксель с линией)
            finalColor = vec3(edge) * currentPixel * LINE_BRIGHTNESS;
            break;
        case 2:// радуга линия 
            {
                float time = worldTime;
                float speed = 0.009 * RAINBOW_SPEED; 
                float scale = 0.3 * RAINBOW_LINE_SCALE;

                float wave = sin(uv.x * 10.0 + uv.x * 10.0) * 0.5 + 0.5;
                float hue = fract(uv.x * scale - time * speed);
                vec3  rainbow = hsv2rgb(vec3(hue, 1.0, 1.0));

                finalColor = vec3(edge) * rainbow * LINE_BRIGHTNESS;
            }
            break;
        case 3: 
            {// радуга 
                float speed = worldTime;
                speed = speed / 10 * RAINBOW_SPEED;
                float r = 0.5 + 0.5 * sin(worldPos.x * 0.05 + speed);
                float g = 0.5 + 0.5 * sin(worldPos.y * 0.05 + speed + 2.0);
                float b = 0.5 + 0.5 * sin(worldPos.z * 0.05 + speed + 4.0);

                vec3 rainbow = vec3(r, g, b);

                finalColor = vec3(edge) * rainbow * LINE_BRIGHTNESS;
            }
            break;
        default:
            finalColor = currentPixel;
    }

    outColor0 = vec4(finalColor, 1.0);
}

