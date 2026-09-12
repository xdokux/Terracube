// Copyright © 2023 Advanced Micro Devices, Inc.

// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files(the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and /or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions :

// The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

vec3 CAS(sampler2D Sampler, vec2 Coords, float LodOffset, float SharpenStrength) {
    // fetch a 3x3 neighborhood around the pixel 'e',
    vec3 e = texture(Sampler, Coords, LodOffset).rgb;
    vec3 a = textureOffset(Sampler, Coords, ivec2(-1, -1), LodOffset).rgb;
    vec3 b = textureOffset(Sampler, Coords, ivec2(0, -1), LodOffset).rgb;
    vec3 c = textureOffset(Sampler, Coords, ivec2(1, -1), LodOffset).rgb;
    vec3 d = textureOffset(Sampler, Coords, ivec2(-1, 0), LodOffset).rgb;
    vec3 f = textureOffset(Sampler, Coords, ivec2(1, 0), LodOffset).rgb;
    vec3 g = textureOffset(Sampler, Coords, ivec2(-1, 1), LodOffset).rgb;
    vec3 h = textureOffset(Sampler, Coords, ivec2(0, 1), LodOffset).rgb;
    vec3 i = textureOffset(Sampler, Coords, ivec2(1, 1), LodOffset).rgb;

    // Soft min and max.
    vec3 mnRGB = min(min(min(d, e), min(f, b)), h);
    vec3 mnRGB2 = min(min(min(mnRGB, a), min(g, c)), i);
    mnRGB += mnRGB2;

    vec3 mxRGB = max(max(max(d, e), max(f, b)), h);
    vec3 mxRGB2 = max(max(max(mxRGB, a), max(g, c)), i);
    mxRGB += mxRGB2;

    // Smooth minimum distance to signal limit divided by smooth max.

    vec3 rcpMxRGB = vec3(1) / mxRGB;
    vec3 ampRGB = clamp((min(mnRGB, 2.0 - mxRGB) * rcpMxRGB), 0, 1);

    // Shaping amount of sharpening.
    ampRGB = inversesqrt(ampRGB);
    float peak = 8.0 - 3.0 * SharpenStrength;
    vec3 wRGB = -vec3(1) / (ampRGB * peak);
    vec3 rcpWeightRGB = vec3(1) / (1.0 + 4.0 * wRGB);

    vec3 window = (b + d) + (f + h);
    vec3 outColor = clamp((window * wRGB + e) * rcpWeightRGB, 0, 1);

    return outColor;
}
