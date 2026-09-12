vec3 hueShift(vec3 color, float degrees) {
    float angle = radians(degrees);
    const mat3 toYIQ = mat3(
        0.299,     0.587,     0.114,
        0.596,    -0.275,    -0.321,
        0.212,    -0.523,     0.311
    );
    const mat3 toRGB = mat3(
        1.0,      0.956,      0.621,
        1.0,     -0.272,     -0.647,
        1.0,     -1.107,      1.705
    );
    vec3 yiq = toYIQ * color;
    float hue = atan(yiq.z, yiq.y) + angle;
    float chroma = length(yiq.yz);
    yiq.y = chroma * cos(hue);
    yiq.z = chroma * sin(hue);
    return clamp(toRGB * yiq, 0.0, 1.0);
}