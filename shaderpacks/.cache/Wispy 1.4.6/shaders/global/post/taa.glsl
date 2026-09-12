// Based on Filmic SMAA & Activision Research

// Reprojection
vec2 toPrevScreenPos(vec2 currScreenPos, float depth, bool isDH) {
    mat4 ProjInv = isDH ? dhProjectionInverse : gbufferProjectionInverse;
    mat4 ModelViewInv = gbufferModelViewInverse;
    mat4 PrevModelView = gbufferPreviousModelView;
    mat4 PrevProj = isDH ? dhPreviousProjection : gbufferPreviousProjection;

    // Simplified view position reconstruction
    vec3 currViewPos = vec3(vec2(ProjInv[0].x, ProjInv[1].y) * (currScreenPos * 2.0 - 1.0) + ProjInv[3].xy, ProjInv[3].z);
    currViewPos /= (ProjInv[2].w * (depth * 2.0 - 1.0) + ProjInv[3].w);

    vec3 currFeetPlayerPos = mat3(ModelViewInv) * currViewPos + ModelViewInv[3].xyz;
    vec3 prevFeetPlayerPos = depth > 0.56 ? currFeetPlayerPos + cameraPosition - previousCameraPosition : currFeetPlayerPos;

    vec3 prevViewPos = mat3(PrevModelView) * prevFeetPlayerPos + PrevModelView[3].xyz;
    vec2 finalPos = vec2(PrevProj[0].x, PrevProj[1].y) * prevViewPos.xy + PrevProj[3].xy;

    return (finalPos / -prevViewPos.z) * 0.5 + 0.5;
}

// Faster AABB Clipping to prevent "ghosting" trails
vec3 clipAABB(vec3 prevColor, vec3 minColor, vec3 maxColor) {
    vec3 pClip = 0.5 * (maxColor + minColor);
    vec3 eClip = 0.5 * (maxColor - minColor) + 0.0001;

    vec3 vClip = prevColor - pClip;
    vec3 aUnit = abs(vClip / eClip);
    float denom = max(aUnit.x, max(aUnit.y, aUnit.z));

    return denom > 1.0 ? pClip + vClip / denom : prevColor;
}

// High-quality Catmull-Rom sampling (keeps the image sharp)
vec3 texture_catmullrom_fast(sampler2D colorTex, vec2 texcoord) {
    vec2 position = resolution * texcoord;
    vec2 centerPosition = floor(position - 0.5) + 0.5;
    vec2 f = position - centerPosition;
    vec2 f2 = f * f;
    vec2 f3 = f * f2;

    float c = 0.5;
    vec2 w0 = -c * f3 + 2.0 * c * f2 - c * f;
    vec2 w1 = (2.0 - c) * f3 - (3.0 - c) * f2 + 1.0;
    vec2 w2 = -(2.0 - c) * f3 + (3.0 - 2.0 * c) * f2 + c * f;
    vec2 w3 = c * f3 - c * f2;

    vec2 w12 = w1 + w2;
    vec2 tc12 = (centerPosition + w2 / w12) * resolutionInv;

    // 5-tap Catmull-Rom is the best balance of speed and clarity
    vec3 color = texture2D(colorTex, vec2(tc12.x, (centerPosition - 1.0) * resolutionInv.y)).rgb * (w12.x * w0.y);
    color += texture2D(colorTex, vec2((centerPosition - 1.0) * resolutionInv.x, tc12.y)).rgb * (w0.x * w12.y);
    color += texture2D(colorTex, tc12).rgb * (w12.x * w12.y);
    color += texture2D(colorTex, vec2((centerPosition + 2.0) * resolutionInv.x, tc12.y)).rgb * (w3.x * w12.y);
    color += texture2D(colorTex, vec2(tc12.x, (centerPosition + 2.0) * resolutionInv.y)).rgb * (w12.x * w3.y);

    return max(vec3(0.0), color);
}

// Optimized neighborhood clipping - Uses Plus-Shape (5 taps) instead of Box (9 taps)
// This reduces texture fetches by 45% per pixel.
vec3 neighbourhoodClipping(sampler2D currTex, vec3 CurrentColor, vec3 prevColor, out vec3 maxColor) {
    vec3 cN = texelFetch2D(currTex, ivec2(gl_FragCoord.xy) + ivec2(0, 1), 0).rgb;
    vec3 cS = texelFetch2D(currTex, ivec2(gl_FragCoord.xy) + ivec2(0, -1), 0).rgb;
    vec3 cE = texelFetch2D(currTex, ivec2(gl_FragCoord.xy) + ivec2(1, 0), 0).rgb;
    vec3 cW = texelFetch2D(currTex, ivec2(gl_FragCoord.xy) + ivec2(-1, 0), 0).rgb;

    vec3 minColor = min(CurrentColor, min(min(cN, cS), min(cE, cW)));
    maxColor = max(CurrentColor, max(max(cN, cS), max(cE, cW)));

    return clipAABB(prevColor, minColor, maxColor);
}

vec3 TAA(inout vec3 Color, vec3 CurrentPos, vec2 PrevCoordCenter, bool IsDH) {
    // Determine previous coordinates
    #if TAA_MODE == 3
    // Closest depth search
    float d0 = CurrentPos.z;
    for(int x = -1; x <= 1; x += 2) {
        for(int y = -1; y <= 1; y += 2) {
            d0 = min(d0, texelFetch2D(depthtex1, ivec2(gl_FragCoord.xy) + ivec2(x, y), 0).x);
        }
    }
    vec2 PrevCoord = toPrevScreenPos(gl_FragCoord.xy * resolutionInv, d0, IsDH);
    #else
    vec2 PrevCoord = PrevCoordCenter;
    #endif

    // Bounds check
    if (any(lessThan(PrevCoord, vec2(0.0))) || any(greaterThan(PrevCoord, vec2(1.0)))) return Color;

    // Sample previous frame
    vec3 PrevColor;
    #if TAA_MODE >= 3
    PrevColor = texture_catmullrom_fast(gaux1, PrevCoord);
    #else
    PrevColor = texture2D(gaux1, PrevCoord).rgb;
    #endif

    if (dot(PrevColor, vec3(1.0)) <= 0.0) return Color;

    // Apply anti-ghosting
    vec3 ClippingMaxColor;
    vec3 ClampedColor = neighbourhoodClipping(colortex0, Color, PrevColor, ClippingMaxColor);

    // Dynamic Blend Factor
    float blendFactor = TAA_BLEND_FACTOR;

    // Motion-based rejection to reduce blur during fast combat
    vec2 velocity = (texcoord - PrevCoord) * resolution;
    blendFactor = mix(blendFactor, 0.1, clamp(length(velocity) * 2.0, 0.0, 1.0));

    Color = mix(Color, ClampedColor, blendFactor);
    return Color;
}
