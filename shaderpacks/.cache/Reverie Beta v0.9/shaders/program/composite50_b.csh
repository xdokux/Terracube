#include "/lib/all_the_libs.glsl"

layout(local_size_x = 16, local_size_y = 16) in;

// Blend weights (SMAA)
#if AA_MODE == 1
const vec2 workGroupsRender = vec2(1.0, 1.0);
#else
const vec2 workGroupsRender = vec2(0.0, 0.0);
#endif

const float SMAA_SEARCH_DISTANCE = 32.0;

float search_length(vec2 Sample, const float Offset) {
    const vec2 SEARCH_TEX_SIZE = vec2(66, 33);

    vec2 Scale = SEARCH_TEX_SIZE * vec2(0.5, -1.0) + vec2(-1, 1);
    vec2 Bias = SEARCH_TEX_SIZE * vec2(Offset, 1) + vec2(0.5, -0.5);

    Scale /= vec2(64, 16);
    Bias /= vec2(64, 16);

    return texture(smaaSearchTexture, Sample * Scale + Bias).r;
}

float SMAASearchXLeft(vec2 texcoord, float end) {

    vec2 e = vec2(0.0, 1.0);
    while (texcoord.x > end && 
           e.g > 0.8281 && // Is there some edge not activated?
           e.r == 0.0) { // Or is there a crossing edge that breaks the line?
        e = texture(image1Sampler, texcoord).rg;
        texcoord = fma(-vec2(2.0, 0.0), resolutionInv.xy, texcoord);
    }

    float offset = fma(-(255.0 / 127.0), search_length( e, 0.0), 3.25);
    return fma(resolutionInv.x, offset, texcoord.x);
}

float SMAASearchXRight(vec2 texcoord, float end) {
    vec2 e = vec2(0.0, 1.0);
    while (texcoord.x < end && 
           e.g > 0.8281 && // Is there some edge not activated?
           e.r == 0.0) { // Or is there a crossing edge that breaks the line?
        e = texture(image1Sampler, texcoord).rg;
        texcoord = fma(vec2(2.0, 0.0), resolutionInv.xy, texcoord);
    }
    float offset = fma(-(255.0 / 127.0), search_length(e, 0.5), 3.25);
    return fma(-resolutionInv.x, offset, texcoord.x);
}

float SMAASearchYUp(vec2 texcoord, float end) {
    vec2 e = vec2(1.0, 0.0);
    while (texcoord.y > end && 
           e.r > 0.8281 && // Is there some edge not activated?
           e.g == 0.0) { // Or is there a crossing edge that breaks the line?
        e = texture(image1Sampler, texcoord).rg;
        texcoord = fma(-vec2(0.0, 2.0), resolutionInv.xy, texcoord);
    }
    float offset = fma(-(255.0 / 127.0), search_length(e.gr, 0.0), 3.25);
    return fma(resolutionInv.y, offset, texcoord.y);
}

float SMAASearchYDown(vec2 texcoord, float end) {
    vec2 e = vec2(1.0, 0.0);
    while (texcoord.y < end && 
           e.r > 0.8281 && // Is there some edge not activated?
           e.g == 0.0) { // Or is there a crossing edge that breaks the line?
        e = texture(image1Sampler, texcoord).rg;
        texcoord = fma(vec2(0.0, 2.0), resolutionInv.xy, texcoord);
    }
    float offset = fma(-(255.0 / 127.0), search_length(e.gr, 0.5), 3.25);
    return fma(-resolutionInv.y, offset, texcoord.y);
}

vec2 sample_area(float d1, float d2, float e1, float e2) {
    vec2 Coord = 16 * round(4 * vec2(e1, e2)) + vec2(d1, d2) + 0.5;
    return texture(smaaAreaTexture, Coord / vec2(160, 560)).rg;
}

void main() {
    ivec2 GlobalPos = ivec2(gl_GlobalInvocationID.xy);
    vec2 Pos = gl_GlobalInvocationID.xy + 0.5;
    vec2 Texcoord = Pos * resolutionInv;

    vec2 Center = texelFetch(image1Sampler, GlobalPos, 0).rg;

    vec4 Color = vec4(0);

    vec4 PosOffset[3];
    PosOffset[0] = fma(resolutionInv.xyxy, vec4(-0.25, -0.125,  1.25, -0.125), Texcoord.xyxy);
    PosOffset[1] = fma(resolutionInv.xyxy, vec4(-0.125, -0.25, -0.125,  1.25), Texcoord.xyxy);

    PosOffset[2] = fma(resolutionInv.xxyy,
                    vec4(-1.0, 1.0, -1.0, 1.0) * float(SMAA_SEARCH_DISTANCE),
                    vec4(PosOffset[0].xz, PosOffset[1].yw));

    // Up
    if(Center.g > 0) {
        vec3 Coords; vec2 d;
        Coords.x = SMAASearchXLeft(PosOffset[0].xy, PosOffset[2].x);
        Coords.y = PosOffset[1].y;
        d.x = Coords.x;

        float eL = texture(image1Sampler, Coords.xy).r;

        Coords.z = SMAASearchXRight(PosOffset[0].zw, PosOffset[2].y);
        d.y = Coords.z;

        d = abs(round(fma(resolution.xx, d, -Pos.xx)));
        d = sqrt(d);

        float eR = textureOffset(image1Sampler, Coords.zy, ivec2(1, 0)).r;

        Color.rg = sample_area(d.x, d.y, eL, eR);
    }
    // Left
    if(Center.r > 0) {
        vec3 Coords; vec2 d;
        Coords.y = SMAASearchYUp(PosOffset[1].xy, PosOffset[2].z);
        Coords.x = PosOffset[0].x;
        d.x = Coords.y;

        float eL = texture(image1Sampler, Coords.xy).g;

        Coords.z = SMAASearchYDown(PosOffset[1].zw, PosOffset[2].w);
        d.y = Coords.z;

        d = abs(round(fma(resolution.yy, d, -Pos.yy)));
        d = sqrt(d);

        float eR = textureOffset(image1Sampler, Coords.xz, ivec2(0, 1)).g;

        Color.ba = sample_area(d.x, d.y, eL, eR);
    }

    imageStore(image0, GlobalPos, Color);
}
