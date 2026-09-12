uniform int frameCounter;

int hilbert(ivec2 p, int level) {
    int d = 0;
    for(int k = 0; k < level; k++) {
        int n = level - k - 1;
        ivec2 r = (p >> n) & 1;
        d += ((3 * r.x) ^ r.y) << (2 * n);
        if (r.y == 0) {
            if (r.x == 1) p = (1 << n) - 1 - p;
            p = p.yx;
        }
    }
    return d;
}

float getNoise(uvec2 p) {
    uint x = uint(hilbert(ivec2(p), 8));
    x += uint(frameCounter) * 0x9E3779B1u;
    x = 0x80000000u + 2654435789u * x;
    return float(x) * 2.328306e-10;
}