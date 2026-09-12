#include "/lib/all_the_libs.glsl"

layout(local_size_x = 16, local_size_y = 16) in;

// Edge detection (SMAA)
#if AA_MODE == 1
const vec2 workGroupsRender = vec2(1.0, 1.0);
#else
const vec2 workGroupsRender = vec2(0.0, 0.0);
#endif

float redmean(vec3 a, vec3 b) {
	float r = step(0.5, mix(a.r, b.r, 0.5));
	vec3 d = a - b;

	return sqrt(dot(d*d, vec3(
		2.0 + r,
		4.0,
		3.0 - r
	)));
}

void main() {
    ivec2 GlobalPos = ivec2(gl_GlobalInvocationID.xy);

    vec3 Center = texelFetch(colortex0, GlobalPos, 0).rgb;
    vec3 Left = texelFetchOffset(colortex0, GlobalPos, 0, ivec2(-1, 0)).rgb;
    vec3 Up = texelFetchOffset(colortex0, GlobalPos, 0, ivec2(0, -1)).rgb;

    vec2 D = vec2(redmean(Center, Left), redmean(Center, Up));

    float Threshold = 0.1;
    Threshold += 0.15 * length(GlobalPos * resolutionInv - 0.5); // Increase near edges of the screen

    vec2 Edges = step(Threshold, D);

    if(all(lessThan(Edges, vec2(0.01)))) {
        imageStore(image1, GlobalPos, vec4(0));
        return;
    }

    vec3 Right = texelFetchOffset(colortex0, GlobalPos, 0, ivec2(1, 0)).rgb;
    vec3 Down = texelFetchOffset(colortex0, GlobalPos, 0, ivec2(0, 1)).rgb;

    vec3 Left2 = texelFetchOffset(colortex0, GlobalPos, 0, ivec2(-2, 0)).rgb;
    vec3 Up2 = texelFetchOffset(colortex0, GlobalPos, 0, ivec2(0, -2)).rgb;

    vec2 Dp = vec2(redmean(Center, Right), redmean(Center, Down));
    vec2 MaxD = max(D, Dp);

    vec2 Dp2 = vec2(redmean(Center, Left2), redmean(Center, Up2));
    MaxD = max(MaxD, Dp2);

    Edges *= step(max(MaxD.x, MaxD.y), D * 2);

    imageStore(image1, GlobalPos, vec4(Edges, 0, 0));
}
