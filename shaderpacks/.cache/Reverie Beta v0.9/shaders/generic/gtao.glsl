// Implementation pretty much entirely from /u/Kvaleya: https://pastebin.com/bKxFnN5i

#define GTAO_LIMIT 100
#define GTAO_RADIUS 3.0
#define GTAO_FALLOFF 1.0
#define GTAO_THICKNESSMIX 0.2
#define GTAO_MAX_STRIDE 32
#define GTAO_SLICES 4

float integrate_arc(float h1, float h2, float n) {
    float cosN = cos(n);
    float sinN = sin(n);
    return 0.25 * (-cos(2.0 * h1 - n) + cosN + 2.0 * h1 * sinN - cos(2.0 * h2 - n) + cosN + 2.0 * h2 * sinN);
}

void slice_sample(vec2 ScreenD, bool IsDH, vec2 aoDir, int i, vec3 ViewPos, vec3 V, inout float closest) {
    vec2 uv = ScreenD + aoDir * i;
    float Depth = get_depth(uv, IsDH);
    vec3 P = screen_view(vec3(uv, Depth), IsDH, true) - ViewPos;
    float current = dot(V, normalize(P));
    float falloff = clamp((GTAO_RADIUS - length(P)) / GTAO_FALLOFF, 0, 1);
    if (current > closest)
        closest = mix(closest, current, falloff);
    closest = mix(closest, current, GTAO_THICKNESSMIX * falloff);
}

float gtao(Positions Pos, bool IsDH, vec3 Normal, out vec3 BentNormal) {
    float stride = min(1 / length(Pos.View) * GTAO_LIMIT, GTAO_MAX_STRIDE);
    vec2 dirMult = stride * resolutionInv;
    vec3 V = -Pos.ViewN;

    float Dither = blue_noise(gl_FragCoord.xy, true).r;
    float AoFinal = 0;
    BentNormal = vec3(0);
    for(int i = 0; i < GTAO_SLICES; i++) {
        float dirAngle = (PI / 16) * (((int(gl_FragCoord.x) + int(gl_FragCoord.y) & 3) << 2) + (int(gl_FragCoord.x) & 3)) + (i + Dither) * TAU / GTAO_SLICES;
        vec2 aoDir = dirMult * vec2(sin(dirAngle), cos(dirAngle));

        vec3 ProjView = screen_view(vec3(Pos.Screen.xy + aoDir, 1), IsDH, true);
        vec3 PlaneNormal = normalize(cross(V, -ProjView));
        vec3 ProjNormal = Normal - PlaneNormal * dot(Normal, PlaneNormal);
        vec3 ProjDir = normalize(normalize(ProjView) + V);
        float n = acosf(dot(-ProjDir, normalize(ProjNormal))) - PI / 2;

        vec2 ScreenD = Pos.Screen.xy + aoDir * (0.25 * ((int(gl_FragCoord.y) - int(gl_FragCoord.x)) & 3) - 0.375 + Dither);

        float c1 = -1, c2 = -1;
        for (int i = -1; i >= -GTAO_SAMPLES; i--) {
            slice_sample(ScreenD, IsDH, aoDir, i, Pos.View, V, c1);
        }
        for (int i = 1; i <= GTAO_SAMPLES; i++) {
            slice_sample(ScreenD, IsDH, aoDir, i, Pos.View, V, c2);
        }

        float H1a = -acosf(c1);
        float H2a = acosf(c2);

        float H1 = n + max(H1a - n, -PI / 2);
        float H2 = n + min(H2a - n, PI / 2);

        float W = integrate_arc(H1, H2, n);
        W = mix(1, W, length(ProjNormal));
        AoFinal += W;

        float BentAngle = atan(
            sin(H2) - sin(H1),
            cos(H1) - cos(H2)
        );
        vec3 SliceTan = normalize(cross(PlaneNormal, ProjDir));
        BentNormal += ProjDir * cos(BentAngle) + SliceTan * sin(BentAngle);
    }
    AoFinal /= GTAO_SLICES;
    BentNormal = normalize(normalize(BentNormal) - 0.5*V);

    return clamp(AoFinal, 0, 1);
}

float ssao(vec3 Normal, vec3 ViewPos, bool IsDH) {

    float Factor = 0, Hits = 0;

    float Dither = dither(gl_FragCoord.xy, true);
    Dither *= 2 * PI;

    for (int i = 0; i < 8; i++) {
        vec3 Sample = vec3(rotate(vogel_disk[i], Dither) * (1 + float(IsDH)), 0);
        Sample *= sign(dot(Normal, Sample));
        Sample += Normal * 0.05;
        Sample += ViewPos;
        vec3 ScreenSamplePos = view_screen(Sample, IsDH, true);
        if(ScreenSamplePos.xy != clamp(ScreenSamplePos.xy, 0, 1)) continue; // Don't sample if offscreen
        bool IsDH2;
        float RealDepth = get_depth(ScreenSamplePos.xy, IsDH2);
        if(IsDH != IsDH2) {
            ScreenSamplePos = view_screen(Sample, IsDH2, true);
        }
        if (RealDepth < 0.56) continue; // Skip hand
        Factor += step(RealDepth + 1e-5, ScreenSamplePos.z);
        Hits++;
    }
    Factor /= Hits == 0 ? 1 : Hits;
    return Factor * 0.4 * (1 + float(IsDH));
}
