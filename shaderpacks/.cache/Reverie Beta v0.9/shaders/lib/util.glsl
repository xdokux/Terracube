float saturate(float x) {
    return clamp(x, 0, 1);
}

vec2 rotate(vec2 X, float Ang) {
    float s = sin(Ang);
    float c = cos(Ang);
    mat2 RotationMat = mat2(
            c, s,
            -s, c
        );
    return RotationMat * X;
}

float get_depth_solid(vec2 ScreenPos, out bool IsDH) {
    float Depth = texture(depthtex1, ScreenPos).x;
    IsDH = false;
    #ifdef DISTANT_HORIZONS
    if (Depth >= 1) {
        Depth = texture(dhDepthTex1, ScreenPos).x;
        IsDH = true;
    }
    #endif
    return Depth;
}

float get_depth(vec2 ScreenPos, out bool IsDH) {
    #if (defined DEFERRED) && (defined VOXY)
        return get_depth_solid(ScreenPos, IsDH);
    #endif
    float Depth = texture(depthtex0, ScreenPos).x;
    IsDH = false;
    #ifdef DISTANT_HORIZONS
    if (Depth >= 1) {
        Depth = texture(dhDepthTex0, ScreenPos).x;
        IsDH = true;
    }
    #endif
    return Depth;
}

float l_depth(float depth, float Near, float Far) {
    return (Near * Far) / (depth * (Near - Far) + Far);
}

float l_depth(float depth) {
    return l_depth(depth, near, far);
}

float l_depth(float depth, bool IsDH) {
    if(IsDH)
        return l_depth(depth, near, dhRenderDistance);
    else
        return l_depth(depth, near, far);
}

float unl_depth(float ldepth, float Near, float Far) {
    return ((Near * Far) / ldepth - Far) / (Near - Far);
}

mat3 tbn_normal(vec3 normal) {
    vec3 tangent = normalize(cross(normal, vec3(0.0, 1.0, 1.0)));
    vec3 bitangent = (cross(tangent, normal));
    return mat3(tangent, bitangent, normal);
}

bool solveQuadratic(float a, float b, float c, out float x1, out float x2) {
    if (b == 0) {
        // Handle special case where the the two vector ray.dir and V are perpendicular
        // with V = ray.orig - sphere.centre
        if (a == 0) return false;
        x1 = 0;
        x2 = sqrt(-c / a);
        return true;
    }
    float discr = b * b - 4 * a * c;

    if (discr < 0) return false;

    float q = (b < 0.f) ? -0.5f * (b - sqrt(discr)) : -0.5f * (b + sqrt(discr));
    x1 = q / a;
    x2 = c / q;

    return true;
}

bool raySphereIntersect(vec3 orig, vec3 dir, float radius, out float t0, out float t1) {
    // They ray dir is normalized so A = 1
    float A = 1;
    float B = 2 * dot(dir, orig);
    float C = dot(orig, orig) - pow2(radius);

    if (!solveQuadratic(A, B, C, t0, t1)) return false;

    if (t0 > t1) {
        float aux = t0;
        t0 = t1;
        t1 = aux;
    }

    return true;
}

vec3 intersectRayWithPlane(vec3 rayOrigin, vec3 rayDirection, float PlaneHeight) {
    float denom = rayDirection.y;

    float pointToRay = PlaneHeight - rayOrigin.y;
    float t = pointToRay / denom;

    // Check if the intersection is in the positive direction of the ray
    if (t >= 0.0) {
        return t * rayDirection;
    }

    // No intersection or the intersection is behind the ray origin
    return vec3(0.0);
}

bool intersect_with_cloud_plane(vec3 CameraPos, inout vec3 StartPos, inout vec3 EndPos, vec3 RayDir, const float LOWER_PLANE, const float UPPER_PLANE) {
    if (CameraPos.y < LOWER_PLANE) {
        StartPos = intersectRayWithPlane(CameraPos, RayDir, LOWER_PLANE);
        EndPos = intersectRayWithPlane(CameraPos, RayDir, UPPER_PLANE);
        if (EndPos == vec3(0) || StartPos == vec3(0)) return false;
    }
    else if (CameraPos.y > UPPER_PLANE) {
        StartPos = intersectRayWithPlane(CameraPos, RayDir, UPPER_PLANE);
        EndPos = intersectRayWithPlane(CameraPos, RayDir, LOWER_PLANE);
        if (EndPos == vec3(0) || StartPos == vec3(0)) return false;
    }
    else {
        StartPos = vec3(0);
        if (RayDir.y > 0) {
            EndPos = intersectRayWithPlane(CameraPos, RayDir, UPPER_PLANE);
        }
        else {
            EndPos = intersectRayWithPlane(CameraPos, RayDir, LOWER_PLANE);
        }
    }

    return true;
}

// https://discord.com/channels/237199950235041794/960945132172111952/1200536680931790878
float SmoothF(float x, float alpha) {
    return x > 0.0 ? pow(x / (x + pow(x, -1.0 / alpha)), alpha / (1.0 + alpha)) : x;
}

float SmoothMin(float a, float b, float alpha) {
    return b - 1.0 + SmoothF(a - b + 1.0, alpha);
}

float SmoothMax(float a, float b, float alpha) {
    return b + 1.0 - SmoothF(1.0 - a + b, alpha);
}

vec3 rgb_to_xyz(vec3 rgb) {
    const mat3 XYZ_MATRIX = mat3(
            0.5149, 0.3244, 0.1607,
            0.3654, 0.6704, 0.0642,
            0.0248, 0.1248, 0.8504
        );
    return XYZ_MATRIX * rgb;
}

const float shadowTexSize = 1.0/shadowMapResolution;

float min_depth_4x4(vec2 texcoord, sampler2D Sampler) {
    float a, b, c, d;
    
    a = min_component(textureGatherOffset(Sampler, texcoord, ivec2(-1, -1)));
    b = min_component(textureGatherOffset(Sampler, texcoord, ivec2(-1,  1)));
    c = min_component(textureGatherOffset(Sampler, texcoord, ivec2( 1, -1)));
    d = min_component(textureGatherOffset(Sampler, texcoord, ivec2( 1,  1)));

    return min_component(vec4(a, b, c, d));
}

float max_depth_4x4(vec2 texcoord, out bool IsDH) {
 
    float a, b, c, d;

    a = max_component(textureGatherOffset(depthtex0, texcoord, ivec2(-1, -1)));
    b = max_component(textureGatherOffset(depthtex0, texcoord, ivec2(-1,  1)));
    c = max_component(textureGatherOffset(depthtex0, texcoord, ivec2( 1, -1)));
    d = max_component(textureGatherOffset(depthtex0, texcoord, ivec2( 1,  1)));
    IsDH = false;

    float D = max_component(vec4(a, b, c, d));
    #ifdef DISTANT_HORIZONS
        if(D >= 1) {
            IsDH = true;
            a = max_component(textureGatherOffset(dhDepthTex0, texcoord, ivec2(-1, -1)));
            b = max_component(textureGatherOffset(dhDepthTex0, texcoord, ivec2(-1,  1)));
            c = max_component(textureGatherOffset(dhDepthTex0, texcoord, ivec2( 1, -1)));
            d = max_component(textureGatherOffset(dhDepthTex0, texcoord, ivec2( 1,  1)));
            return max_component(vec4(a, b, c, d));
        }
    #endif
    return D;
}

bool ray_intersect(vec3 WorldPos, inout vec3 StartPos, inout vec3 EndPos, vec3 PlayerPosN, const float MAX_HEIGHT) {
    if (WorldPos.y <= MAX_HEIGHT) {
        if (EndPos.y + cameraPosition.y > MAX_HEIGHT)
            EndPos = intersectRayWithPlane(WorldPos, PlayerPosN, MAX_HEIGHT);
        if (EndPos == vec3(0)) return false;
    }
    else {
        if (EndPos.y + cameraPosition.y > MAX_HEIGHT) return false;
        StartPos = intersectRayWithPlane(WorldPos, PlayerPosN, MAX_HEIGHT);
        if (StartPos == vec3(0)) return false;
    }

    return true;
}

// Nerfs sample count as the ray direction approaches the zenith
float adaptive_samples(const float BASE_SAMPLES, float VdotU) {
    return ceil(((1-abs(VdotU)) * 0.5 + 0.5) * BASE_SAMPLES);
}

vec3 blend_vl(vec3 Color, mat2x3 VlData) {
    return Color * VlData[1] + VlData[0];
}

vec3 blend_vl(vec3 Color, vec4 VlData) {
    return Color * VlData.a + VlData.rgb;
}

float correct_hand_depth(float Depth, bool IsDH, out bool IsHand) {
    IsHand = Depth <= 0.56;
    if (IsHand) {
        Depth = Depth * 2 - 1;
        Depth /= MC_HAND_DEPTH;
        Depth = Depth * 0.5 + 0.5;
    }
    return Depth;
}

vec2 to_spherical(vec3 dir) {
    float u = 0.5f + (atan(dir.z, dir.x) / TAU);

    float v = 0.5f - (asin(dir.y) / PI);

    return vec2(u, v);
}

vec3 from_spherical(vec2 uv) {
    float theta = (uv.x - 0.5) * TAU; // longitude
    float phi   = (0.5 - uv.y) * PI;        // latitude

    float cosPhi = cos(phi);

    vec3 dir;
    dir.x = cosPhi * cos(theta);
    dir.y = sin(phi);
    dir.z = cosPhi * sin(theta);

    return dir;
}

float quantize_16bit(float X) {
    return floor(X * 65535.0 + 0.5) / 65535.0;
}