void getMaterial(
    float mask,
    out float foliage,
    out float size,
    out float strength
) {
    foliage = 0.0;
    if (abs(mask - 1.0) < 0.1 || abs(mask - 13.0) < 0.1) foliage = 1.0;
    if (abs(mask - 0.5) < 0.1 || abs(mask - 15.0) < 0.1) foliage = 0.1;
    if (abs(mask - 12.0) < 0.1 || abs(mask - 19.0) < 0.1 || abs(mask - 26.0) < 0.1) foliage = 0.5;

    size = 6.0;
    if (abs(mask - 1.0) < 0.1 || abs(mask - 12.0) < 0.1 || abs(mask - 26.0) < 0.1 || abs(mask - 13.0) < 0.1 || abs(mask - 14.0) < 0.1 || abs(mask - 19.0) < 0.1) size = 16.0;
    if (abs(mask - 2.0) < 0.1 || abs(mask - 25.0) < 0.1) size = 64.0;
    if (abs(mask - 20.0) < 0.1) size = 250.0;

    strength = 0.6;
    if (abs(mask - 1.0) < 0.1 || abs(mask - 13.0) < 0.1 || abs(mask - 19.0) < 0.1) strength = 1.0;
    if (abs(mask - 2.0) < 0.1 || abs(mask - 12.0) < 0.1 || abs(mask - 26.0) < 0.1 || abs(mask - 25.0) < 0.1) strength = 2.0;
    if (abs(mask - 20.0) < 0.1) strength = 8.0;
}