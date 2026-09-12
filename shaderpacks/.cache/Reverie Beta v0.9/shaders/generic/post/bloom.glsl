
// https://www.iryoku.com/next-generation-post-processing-in-call-of-duty-advanced-warfare/
vec3 blur6x6(sampler2D image, vec2 texcoord) {
    vec3 Color = texture(image, texcoord).rgb;

    // Sample corners
    Color += textureOffset(image, texcoord, ivec2(-2, -2)).rgb * 0.125;
    Color += textureOffset(image, texcoord, ivec2(2, -2)).rgb * 0.125;
    Color += textureOffset(image, texcoord, ivec2(-2, 2)).rgb * 0.125;
    Color += textureOffset(image, texcoord, ivec2(2, 2)).rgb * 0.125;

    // Sample in a + shape
    Color += textureOffset(image, texcoord, ivec2(0, -2)).rgb * 0.25;
    Color += textureOffset(image, texcoord, ivec2(0, 2)).rgb * 0.25;
    Color += textureOffset(image, texcoord, ivec2(-2, 0)).rgb * 0.25;
    Color += textureOffset(image, texcoord, ivec2(2, 0)).rgb * 0.25;

    // Sample closer corners
    Color += textureOffset(image, texcoord, ivec2(-1, -1)).rgb * 0.5;
    Color += textureOffset(image, texcoord, ivec2(1, -1)).rgb * 0.5;
    Color += textureOffset(image, texcoord, ivec2(-1, 1)).rgb * 0.5;
    Color += textureOffset(image, texcoord, ivec2(1, 1)).rgb * 0.5;

    return Color / 4.5;
}

// 5 texture samples instead of 9
vec4 blur3x3(sampler2D image, vec2 texcoord) {
    vec4 Color = vec4(0);
    vec2 Off1 = vec2(-0.3333, 1.0) * resolutionInv;
    vec2 Off2 = vec2(1.0, 0.3333) * resolutionInv;
    Color += textureLod(image, texcoord, 0) * 0.25;
    Color += textureLod(image, texcoord + Off1, 0) * 0.1875;
    Color += textureLod(image, texcoord - Off1, 0) * 0.1875;
    Color += textureLod(image, texcoord + Off2, 0) * 0.1875;
    Color += textureLod(image, texcoord - Off2, 0) * 0.1875;
    return Color;
}


vec2 adjust_vertex_position(float TileSize, float MaxSize, float TileOffset, vec2 glPos) {
    vec2 TileSizeClamped = vec2(aspectRatio, 1) * vec2(TileSize);
    float Scale = max(1, min_component(TileSizeClamped) / min_component(resolution * MaxSize));
    glPos = (glPos * TileSizeClamped + TileOffset * vec2(aspectRatio, 1)) / Scale * resolutionInv;
    return glPos;
}