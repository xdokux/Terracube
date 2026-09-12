// From filmic SMAA presentation: https://research.activision.com/publications/archives/filmic-smaasharp-morphological-and-temporal-antialiasing
vec3 texture_catmullrom_fast(sampler2D colorTex, vec2 texcoord) {
    vec2 position = resolution * texcoord;
    vec2 centerPosition = floor(position - 0.5) + 0.5;
    vec2 f = position - centerPosition;
    vec2 f2 = f * f;
    vec2 f3 = f * f2;

    float c = 0.65;
    vec2 w0 = -c * f3 + 2.0 * c * f2 - c * f;
    vec2 w1 = (2.0 - c) * f3 - (3.0 - c) * f2 + 1.0;
    vec2 w2 = -(2.0 - c) * f3 + (3.0 - 2.0 * c) * f2 + c * f;
    vec2 w3 = c * f3 - c * f2;

    vec2 w12 = w1 + w2;
    vec2 tc12 = (centerPosition + w2 / w12) * resolutionInv;
    vec3 centerColor = texture_rgbm(colorTex, vec2(tc12.x, tc12.y)).rgb;

    vec2 tc0 = (centerPosition - 1.0) * resolutionInv;
    vec2 tc3 = (centerPosition + 2.0) * resolutionInv;
    vec4 color = vec4(texture_rgbm(colorTex, vec2(tc12.x, tc0.y)).rgb, 1.0) * (w12.x * w0.y) +
            vec4(texture_rgbm(colorTex, vec2(tc0.x, tc12.y)).rgb, 1.0) * (w0.x * w12.y) +
            vec4(centerColor, 1.0) * (w12.x * w12.y) +
            vec4(texture_rgbm(colorTex, vec2(tc3.x, tc12.y)).rgb, 1.0) * (w3.x * w12.y) +
            vec4(texture_rgbm(colorTex, vec2(tc12.x, tc3.y)).rgb, 1.0) * (w12.x * w3.y);
    return color.rgb / color.a;
}

// from http://www.java-gaming.org/index.php?topic=35123.0
vec4 cubic(float v) {
    vec4 n = vec4(1.0, 2.0, 3.0, 4.0) - v;
    vec4 s = n * n * n;
    float x = s.x;
    float y = s.y - 4.0 * s.x;
    float z = s.z - 4.0 * s.y + 6.0 * s.x;
    float w = 6.0 - x - y - z;
    return vec4(x, y, z, w) * (1.0 / 6.0);
}

vec4 texture_bicubic(sampler2D sampler, vec2 texCoords) {
    vec2 texSize = resolution;
    vec2 invTexSize = 1.0 / texSize;

    texCoords = texCoords * texSize - 0.5;

    vec2 fxy = fract(texCoords);
    texCoords -= fxy;

    vec4 xcubic = cubic(fxy.x);
    vec4 ycubic = cubic(fxy.y);

    vec4 c = texCoords.xxyy + vec2(-0.5, +1.5).xyxy;

    vec4 s = vec4(xcubic.xz + xcubic.yw, ycubic.xz + ycubic.yw);
    vec4 offset = c + vec4(xcubic.yw, ycubic.yw) / s;

    offset *= invTexSize.xxyy;

    vec4 sample0 = texture(sampler, offset.xz);
    vec4 sample1 = texture(sampler, offset.yz);
    vec4 sample2 = texture(sampler, offset.xw);
    vec4 sample3 = texture(sampler, offset.yw);

    float sx = s.x / (s.x + s.y);
    float sy = s.z / (s.z + s.w);

    return mix(
        mix(sample3, sample2, sx), mix(sample1, sample0, sx), sy);
}

// The MIT License
// Copyright © 2013 Inigo Quilez
// https://www.youtube.com/c/InigoQuilez
// https://iquilezles.org/
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions: The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software. THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
vec4 textureNice(sampler2D sam, vec2 uv)
{
    float textureResolution = float(textureSize(sam, 0).x);
    uv = uv * textureResolution + 0.5;
    vec2 iuv = floor(uv);
    vec2 fuv = fract(uv);
    uv = iuv + fuv * fuv * (3.0 - 2.0 * fuv);
    uv = (uv - 0.5) / textureResolution;
    return texture(sam, uv);
}

// From "Filmic SMAA - Sharp Morphological and Temporal Antialiasing"
vec3 textureNicest(sampler2D sam, vec2 uv) {
    float textureResolution = float(textureSize(sam, 0).x);
    uv = uv * textureResolution + 0.5;
    vec2 iuv = floor(uv);
    vec2 fuv = fract(uv);
    fuv = max(min((fuv - 0.2) / (1 - 0.4), 1), 0);
    uv = iuv + fuv * fuv * (3.0 - 2.0 * fuv);
    uv = (uv - 0.5) / textureResolution;
    return texture_rgbm(sam, uv);
}
