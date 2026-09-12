bool is_in_voxel_range(vec3 PlayerPos) {
    return all(greaterThan(PlayerPos, vec3(0))) &&
        all(lessThan(PlayerPos, voxelDistance * vec3(2, 1, 2)));
}

bool should_id_be_voxelised(float Id) {
    return Id != MATERIAL_FLOODFILL_PASSTHROUGH;
}

vec3 get_voxel_pos(vec3 PlayerPos) {
    return PlayerPos + voxelDistance * vec3(1, 0.5, 1) + cameraPositionFract;
}

vec3 hardcoded_light_colors(float Id, vec3 FallbackColor) {
    FallbackColor = rgb_to_hsv(FallbackColor);
    vec3 Color;
    switch(uint(Id)) {
        case 21:
            Color = vec3(0, 1, 1);
            break;
        case 22:
            Color = vec3(0.06, 1, 1);
            break;
        case 23:
            Color = vec3(0.08, 1.0, 0.8);
            break;
        case 24:
            Color = vec3(0.2, 0.75, 1);
            break;
        case 25:
            Color = vec3(0.4, 0.5, 1);
            break;
        case 26:
            Color = vec3(0.55, 0.75, 1);
            break;
        case 27:
            Color = vec3(0.75, 0.7, 1);
            break;
        default:
            Color = vec3(FallbackColor.r, min(1, FallbackColor.g + 0.3), 1);
    }

    Color.rgb = mix(Color, FallbackColor, vec3(0.3, 0.25, 0));
    
    return srgb_linear(hsv_to_rgb(Color));
}