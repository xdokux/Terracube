bool is_in_voxel_range(vec3 PlayerPos) {
    return all(greaterThan(PlayerPos, vec3(0))) &&
        all(lessThan(PlayerPos, vec3(voxelDistance * 2)));
}

bool should_id_be_voxelised(float Id) {
    return Id != 10020;
}

vec3 get_voxel_pos(vec3 PlayerPos) {
    return PlayerPos + voxelDistance + cameraPositionFract;
}

vec3 hardcoded_light_colors(float Id, vec3 FallbackColor) {
    FallbackColor = rgb_to_hsv(FallbackColor);
    vec3 Color;
    switch(uint(Id)) {
        case 10021:
            Color = vec3(0, 1, 1);
            break;
        case 10022:
            Color = vec3(0.07, 0.7, 1);
            break;
        case 10023:
            Color = vec3(0.1, 0.5, 0.8);
            break;
        case 10024:
            Color = vec3(0.2, 0.75, 0.6);
            break;
        case 10025:
            Color = vec3(0.45, 0.2, 0.8);
            break;
        case 10026:
            Color = vec3(0.55, 0.75, 1);
            break;
        case 10027:
            Color = vec3(0.75, 0.5, 1);
            break;
        default:
            Color = vec3(FallbackColor.r, min(1, FallbackColor.g + 0.3), 1);
    }

    return to_linear(hsv_to_rgb(Color));
}

vec3 filter_floodfill(sampler3D Sampler, vec3 FragPos) {
    vec3 Pos = FragPos / voxelDistance / 2; 
    vec3 C = texture(Sampler, Pos).rgb; // Center

    return sqrt(C) * 6;
}

vec3 sample_floodfill(vec3 PlayerPos, vec3 Normal, vec3 Color) {
    #if (defined COLORED_LIGHTS) && (!defined DH_TERRAIN) && (!defined VOXY_TERRAIN)
        vec3 PlayerPosAbs = get_voxel_pos(PlayerPos) + view_player(Normal, false) * 0.065;

        if(is_in_voxel_range(PlayerPosAbs)) {
            vec3 VoxelData;
            if(frameCounter % 2 == 1) {
                VoxelData = filter_floodfill(voxelImgSampler_a, PlayerPosAbs);
            } else {
                VoxelData = filter_floodfill(voxelImgSampler_b, PlayerPosAbs);
            }

            float Fade = shadow_fade(PlayerPos, voxelDistance);
            Color = mix(VoxelData.rgb, Color, Fade);
        }
    #endif
    return Color;
}