
layout(std430, binding = 0) buffer VoxelGrid {
    // 262144 * 2 = 524288
    int voxels[524288]; 
};

// These offsets act as our "A" and "B" switches
const int OFFSET_A = 0;
const int OFFSET_B = 262144;

vec3 getVoxelColor(ivec3 pos, float isUnderWater,float depthAllLinear, float depthSolidLinear,bool isWater) {
    // 1. Boundary check
    if (pos.x < 0 || pos.x >= 64 || pos.y < 0 || pos.y >= 64 || pos.z < 0 || pos.z >= 64) {
        return vec3(0.0);
    }
    
    // 2. Read and unpack
    // (Assuming OFFSET_A is defined as 0 in your all_the_libs.glsl)
    int data = voxels[pos.x + (pos.y * 64) + (pos.z * 4096) + OFFSET_A];
    int id = data >> 4;
    int lvl = data & 15;
    
    if (lvl == 0) return vec3(0.0);
    
    // 3. Convert to float intensity
    float rawIntensity = float(lvl) / 15.0;
    float intensity = pow(rawIntensity, 2.2);
    
    // 4. Map IDs to colors
    vec3 col = vec3(0.0);
    if (id == 2) col = vec3(0.2, 0.6, 1.0);      // Soul Torch
    else if (id == 3) col = vec3(0.7, 0.4, 0.1); // Normal Torch
    else if (id == 4) col = vec3(0.7, 0.2, 0.1); // Redstone
    else if (id == 5) col = vec3(0.5, 0.0, 0.5);
    else if (id == 6) col = vec3(0.5, 0.5, 0.5); // End Rod

   if(isWater && (isUnderWater > 0.5 || isEyeInWater == 1)) {
    
    // 2. The thickness of the water is the distance between the surface and the floor
    float waterThickness = max(0.0, depthSolidLinear - depthAllLinear);
    
    // If the camera is actually completely submerged, the water thickness 
    // is just the distance from the camera to the solid block.
    if (isEyeInWater == 1) {
        waterThickness = depthSolidLinear; 
    }

    // Tint the light source slightly bluish due to being underwater
    col *= vec3(0.8, 0.9, 1.0) * 1.3;

    // 3. Apply Beer-Lambert Law using the true water thickness
    vec3 absorptionCoeff = vec3(0.15, 0.05, 0.02); 
    col *= exp(-absorptionCoeff * waterThickness); 
}
    
    return col * intensity;
}

// Takes a position and returns the fully smoothed trilinear color
vec3 getTrilinearLight(vec3 samplePos, float isUnderWater, float depthAllLinear, float depthSolidLinear, bool isWater) {
    ivec3 base = ivec3(floor(samplePos));
    vec3 fractPos = fract(samplePos);
    
    // Smootherstep curve
    vec3 blend = fractPos * fractPos * fractPos * (fractPos * (fractPos * 6.0 - 15.0) + 10.0);

    vec3 c000 = getVoxelColor(base + ivec3(0, 0, 0), isUnderWater, depthAllLinear, depthSolidLinear, isWater);
    vec3 c100 = getVoxelColor(base + ivec3(1, 0, 0), isUnderWater, depthAllLinear, depthSolidLinear, isWater);
    vec3 c010 = getVoxelColor(base + ivec3(0, 1, 0), isUnderWater, depthAllLinear, depthSolidLinear, isWater);
    vec3 c110 = getVoxelColor(base + ivec3(1, 1, 0), isUnderWater, depthAllLinear, depthSolidLinear, isWater);
    vec3 c001 = getVoxelColor(base + ivec3(0, 0, 1), isUnderWater, depthAllLinear, depthSolidLinear, isWater);
    vec3 c101 = getVoxelColor(base + ivec3(1, 0, 1), isUnderWater, depthAllLinear, depthSolidLinear, isWater);
    vec3 c011 = getVoxelColor(base + ivec3(0, 1, 1), isUnderWater, depthAllLinear, depthSolidLinear, isWater);
    vec3 c111 = getVoxelColor(base + ivec3(1, 1, 1), isUnderWater, depthAllLinear, depthSolidLinear, isWater);

    vec3 c00 = mix(c000, c100, blend.x);
    vec3 c10 = mix(c010, c110, blend.x);
    vec3 c01 = mix(c001, c101, blend.x);
    vec3 c11 = mix(c011, c111, blend.x);

    vec3 c0 = mix(c00, c10, blend.y);
    vec3 c1 = mix(c01, c11, blend.y);

    return mix(c0, c1, blend.z);
}

int getIndex(ivec3 pos) {
    return pos.x + (pos.y * 64) + (pos.z * 4096);
}

float getIGN(vec2 pixelCoords) {
    vec3 magic = vec3(0.06711056, 0.00583715, 52.9829189);
    return fract(magic.z * fract(dot(pixelCoords, magic.xy)));
}


float random(vec2 coords) {
    return fract(sin(dot(coords.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

float random3D(vec3 p) {
    return fract(sin(dot(p, vec3(12.9898, 78.233, 45.543))) * 43758.5453);
}


vec3 rotateAxis(vec3 p, vec3 axis, float angle) {
    return mix(dot(axis, p) * axis, p, cos(angle)) + cross(axis, p) * sin(angle);
}

vec3 project_and_divide(mat4 Projection_mat, vec3 x) {
    vec4 HomogeneousPos = Projection_mat * vec4(x, 1);
    return HomogeneousPos.xyz / HomogeneousPos.w;
}

vec3 to_view_pos(vec3 p, bool IsDH) {
    p = p * 2 - 1;
    if (IsDH)
        return project_and_divide(dhProjectionInverse, p);
    else
        return project_and_divide(gbufferProjectionInverse, p);
}

vec3 view_screen(vec3 x, bool IsDH) {
    if (IsDH)
        x = project_and_divide(dhProjection, x);
    else
        x = project_and_divide(gbufferProjection, x);
    x = x * 0.5 + 0.5;
    return x;
}





vec3 to_player_pos(vec3 p) {
    return mat3(gbufferModelViewInverse) * p;
}

//Rain Ripple helper function
float get_rain_ripples(vec3 worldPos, vec3 normal) {
    if (wetness < 0.01 || normal.y < 0.5) return 0.0;

    float t = frameTimeCounter * 2.3 * (1.0 + smoothstep(0.0, 1.0, wetness));
    vec2 p = worldPos.xz * 1.5;
    
    float ripples = 0.0;
    float weight = 1.0;
    
    for(int i = 0; i < 4; i++) {
        vec2 noiseUV = p + vec2(t * 0.1, t * 0.05);
        float n = texture(noisetex, noiseUV * 0.1).r;
        float r = distance(fract(p * weight + n), vec2(0.5));
        ripples += sin(r * 20.0 - t * 3.0) * (1.0 - smoothstep(0.0, 0.4, r)) * weight;
        weight *= 0.7;
        p *= 1.8;
    }
    
    return ripples * rainStrength;
}

float get_after_rain(){
    if(rainStrength < 0.5 && wetness > 0.01)
    return 1.0;
    else
    return 0.0;
}

//calculate rain ripple normals
vec3 get_rain_ripple_normal(vec3 worldPos, vec3 normal) {
    float delta = 0.1;
    float h = get_rain_ripples(worldPos, normal);
    float hx = get_rain_ripples(worldPos + vec3(delta, 0.0, 0.0), normal);
    float hz = get_rain_ripples(worldPos + vec3(0.0, 0.0, delta), normal);
    
    vec3 bump = vec3(hx - h, 0.2, hz - h);
    return normalize(normal + bump * 0.1);
}


vec3 player_view(vec3 p) {
    return mat3(gbufferModelView) * p;
}

float linearize_depth(float D) {
    return near / (1 - D);
}

float ld_exact(float depth, float near, float far) {
    return (near * far) / (depth * (near - far) + far);
}

// Creates a TBN matrix from a normal and a tangent
mat3 tbnNormalTangent(vec3 normal, vec3 tangent) {
    // For DirectX normal mapping you want to switch the order of these
    vec3 bitangent = cross(normal, tangent);
    return mat3(tangent, bitangent, normal);
}

// Creates a TBN matrix from just a normal
// The tangent version is needed for normal mapping because
//   of face rotation
mat3 tbnNormal(vec3 normal) {
    // This could be
    // normalize(vec3(normal.y - normal.z, -normal.x, normal.x))
    vec3 tangent = normalize(cross(normal, vec3(0, 1, 1)));
    return tbnNormalTangent(normal, tangent);
}

float get_luminance(vec3 Color) {
    return 0.299 * Color.r + 0.587 * Color.g + 0.114 * Color.b;
}

vec2 rotate(vec2 P, float Ang) {
    float cosT = cos(Ang);
    float sinT = sin(Ang);
    return vec2(
        P.x * cosT - P.y * sinT,
        P.y * cosT + P.x * sinT
    );
}

float len2(vec2 v) {
    return dot(v, v);
}

float len2(vec3 v) {
    return dot(v, v);
}

float pow2(float x) {
    return x * x;
}

float pow4(float x) {
    return pow2(pow2(x));
}

vec2 pow2(vec2 x) {
    return x * x;
}

vec2 pow4(vec2 x) {
    return pow2(pow2(x));
}

vec3 pow2(vec3 x) {
    return x * x;
}

vec3 pow4(vec3 x) {
    return pow2(pow2(x));
}

vec4 pow2(vec4 x) {
    return x * x;
}

vec4 pow4(vec4 x) {
    return pow2(pow2(x));
}

float min_component(vec2 a) {
    return min(a.x, a.y);
}
float min_component(vec3 a) {
    return min(a.x, min(a.y, a.z));
}
float min_component(vec4 a) {
    return min(a.x, min(a.y, min(a.z, a.w)));
}

float max_component(vec2 a) {
    return max(a.x, a.y);
}
float max_component(vec3 a) {
    return max(a.x, max(a.y, a.z));
}
float max_component(vec4 a) {
    return max(a.x, max(a.y, max(a.z, a.w)));
}

float cs_phase(float Mu, float g) {
    float g2 = g * g;
    float A = 3 * (1 - g2) * (1 + Mu * Mu);
    float B = 8 * PI * (2 + g2) * pow(1 + g2 - 2 * g * Mu, 1.5);
    return A / B;
}

float xlf_phase(float angle, const float g)
{
	float g2 = g * g;
	const float k = 3.0/2.0;
	float denom = (1 + g2 - 2 * g * angle);
	float result = k * ((1-g2)/(2+g2)) * ((1 + angle*angle) / denom) + g*angle;
	return 1.0/(4.0*PI) * result;
}