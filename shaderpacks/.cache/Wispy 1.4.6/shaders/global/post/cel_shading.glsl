float getEdgeFactor(vec2 texcoord, float thickness) {
    vec2 offset = resolutionInv * max(thickness, 1.0);
    float d0 = texture2D(depthtex1, texcoord).r;
    if (d0 >= 0.9999) return 0.0;
    float d1 = texture2D(depthtex1, texcoord + vec2(offset.x, 0)).r;
    float d2 = texture2D(depthtex1, texcoord - vec2(offset.x, 0)).r;
    float d3 = texture2D(depthtex1, texcoord + vec2(0, offset.y)).r;
    float d4 = texture2D(depthtex1, texcoord - vec2(0, offset.y)).r;
    float diff1 = abs(d0 - d1);
    float diff2 = abs(d0 - d2);
    float diff3 = abs(d0 - d3);
    float diff4 = abs(d0 - d4);
    float horizontalEdge = abs(diff1 - diff2);
    float verticalEdge = abs(diff3 - diff4);
    float maxDiff = max(max(diff1, diff2), max(diff3, diff4));
    float edgeSharpness = max(horizontalEdge, verticalEdge);
    if (maxDiff < 0.0001 || maxDiff > 0.04 || edgeSharpness < 0.0005) return 0.0;

    vec3 viewPos = to_view_pos(vec3(texcoord, d0), false);
    float dist = length(viewPos);
    float distFade = 1.0 - smoothstep(2.0, 200.0, dist);
    float baseThreshold = CEL_OUTLINE_DEPTH_THRESHOLD;

    float distThreshold = baseThreshold * (1.0 + dist * 0.005);

    float edge = smoothstep(distThreshold * 0.1, distThreshold * 1.5, maxDiff);
    return edge * distFade;
}

vec3 applyCelShading(vec3 color, vec2 texcoord) {
    float edgeFactor = getEdgeFactor(texcoord, CEL_OUTLINE_THICKNESS);
    vec3 outlineColor = vec3(CEL_OUTLINE_R, CEL_OUTLINE_G, CEL_OUTLINE_B);
    float finalEdgeFactor = edgeFactor * CEL_OUTLINE_TRANSPARENCY;
    return mix(color, outlineColor, finalEdgeFactor);
}
