// AETHER — shared gbuffer vertex/fragment bodies (labPBR + POM)
// Define GBUFFER_VSH or GBUFFER_FSH before including.
// Optional: TERRAIN (enables mc_Entity ids + parallax)

#ifdef GBUFFER_VSH
varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 glcolor;
varying vec3 normalV;
varying vec4 tangentV;
varying vec3 viewPosV;
varying vec4 tileBounds;   // atlas-space min/max of this texture tile
varying float matId;

#ifdef TERRAIN
attribute vec4 mc_Entity;
#endif
attribute vec4 at_tangent;
attribute vec4 mc_midTexCoord;
uniform int worldTime;
uniform float frameTimeCounter;
uniform float rainStrength;

void gbufferVertex() {
    vec4 pos = gl_Vertex;
    float id = 0.0;
#ifdef TERRAIN
    id = mc_Entity.x;
    // Gentle wind sway for foliage
    if (id == 10001.0 || id == 10002.0) {
        float phase = dot(pos.xz, vec2(0.5, 0.8)) + frameTimeCounter * (1.4 + rainStrength * 1.6);
        float amp = 0.035 * (1.0 + rainStrength * 1.5);
        if (id == 10002.0 || gl_MultiTexCoord0.t < 0.5)
            pos.xz += vec2(sin(phase), cos(phase * 0.7)) * amp;
    }
#endif
    gl_Position = gl_ModelViewProjectionMatrix * pos;
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    glcolor  = gl_Color;
    normalV  = normalize(gl_NormalMatrix * gl_Normal);
    tangentV = vec4(normalize(gl_NormalMatrix * at_tangent.xyz), at_tangent.w);
    viewPosV = (gl_ModelViewMatrix * pos).xyz;

    // Tile bounds: half-extent from midTexCoord is constant per quad
    vec2 mid = (gl_TextureMatrix[0] * mc_midTexCoord).xy;
    vec2 halfSize = abs(texcoord - mid);
    tileBounds = vec4(mid - halfSize, mid + halfSize);
    matId = id;
}
#endif

#ifdef GBUFFER_FSH
uniform sampler2D texture;
uniform sampler2D normals;    // labPBR _n: rg=normal, b=AO, a=height
uniform sampler2D specular;   // labPBR _s: r=smoothness, g=f0, a=emission
varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 glcolor;
varying vec3 normalV;
varying vec4 tangentV;
varying vec3 viewPosV;
varying vec4 tileBounds;
varying float matId;

// Confine a UV to the current atlas tile by CLAMPING (never fract): the
// parallax march can neither bleed into a neighbouring texture nor
// seam-jump when it crosses a tile edge. Tiny inset avoids mip edge bleed.
vec2 clampTile(vec2 uv) {
    vec2 inset = (tileBounds.zw - tileBounds.xy) * 0.0005;
    return clamp(uv, tileBounds.xy + inset, tileBounds.zw - inset);
}

void gbufferFragment(float materialClass) {
    vec2 uv = texcoord;
    vec3 N = normalize(normalV);
    float smoothness = 0.0;
    float f0 = 0.015;
    float emission = 0.0;

#ifdef LABPBR
    // ---- Stable orthonormal TBN, rebuilt per fragment (Gram-Schmidt) ----
    // Re-orthogonalising the interpolated tangent against the geometric
    // normal removes the tangent drift that makes normals swim across a face.
    // TBN is orthonormal → its transpose is its inverse, so view↔tangent
    // transforms stay exact and the parallax offset can't skew.
    vec3 T = tangentV.xyz - N * dot(N, tangentV.xyz);
    T = length(T) > 1e-6 ? normalize(T) : vec3(1.0, 0.0, 0.0);
    vec3 B = normalize(cross(N, T)) * sign(tangentV.w);
    mat3 TBN = mat3(T, B, N);

    #if defined POM && defined TERRAIN
    // Parallax occlusion mapping from labPBR height (normals alpha).
    // Flat/unbound heightmaps read 1.0 → zero offset, so this is always safe.
    float pomDist = length(viewPosV);
    if (texture2D(normals, uv).a < 0.999 && pomDist < POM_DISTANCE) {
        // View dir in tangent space (v * M == transpose(M) * v == inverse here).
        vec3 tsView = normalize(-viewPosV) * TBN;
        vec2 tileSize = tileBounds.zw - tileBounds.xy;

        // Fade parallax to zero at grazing angles and at distance so the
        // offset can never run away — that runaway is the sliding/drifting.
        float fade = smoothstep(0.12, 0.42, tsView.z)
                   * smoothstep(POM_DISTANCE, POM_DISTANCE * 0.55, pomDist);
        if (tileSize.x > 0.25 || tileSize.y > 0.25) fade = 0.0; // CTM / merged quads

        if (fade > 0.01) {
            vec2 maxOffset = (tsView.xy / max(tsView.z, 0.30)) * POM_DEPTH * tileSize * fade;
            float layerStep = 1.0 / float(POM_SAMPLES);
            vec2 uvStep = maxOffset * layerStep;

            vec2  curUV = uv;
            float layerD = 0.0;
            float curH = 1.0 - texture2D(normals, curUV).a;
            vec2  prevUV = curUV;
            float prevH = curH;
            float prevD = 0.0;

            for (int i = 0; i < POM_SAMPLES; i++) {
                if (layerD >= curH) break;
                prevUV = curUV; prevH = curH; prevD = layerD;
                curUV  = clampTile(curUV - uvStep);
                layerD += layerStep;
                curH   = 1.0 - texture2D(normals, curUV).a;
            }
            // Linear occlusion interpolation between the two bracketing layers
            // → smooth depth, no stair-step quantisation (the shimmer/jitter).
            float after  = curH  - layerD;
            float before = prevH - prevD;
            float w = clamp(after / (after - before + 1e-5), 0.0, 1.0);
            uv = clampTile(mix(curUV, prevUV, w));
        }
    }
    #endif

    // ---- tangent-space normal map (guard against unbound-white samplers) ----
    vec4 nTex = texture2D(normals, uv);
    bool nValid = nTex.x + nTex.y > 0.001 && !(nTex.x > 0.999 && nTex.y > 0.999);
    if (nValid) {
        vec3 tn;
        tn.xy = nTex.xy * 2.0 - 1.0;
        #ifdef NORMAL_DX
        tn.y = -tn.y; // pack uses DirectX-convention normals (inverted green)
        #endif
        tn.z = sqrt(max(1.0 - dot(tn.xy, tn.xy), 0.0));
        N = normalize(TBN * tn);
    }

    // ---- specular (white = missing data, not chrome) ----
    vec4 sTex = texture2D(specular, uv);
    if (!(sTex.r > 0.999 && sTex.g > 0.999 && sTex.b > 0.999)) {
        smoothness = sTex.r;
        f0 = max(sTex.g, 0.015);
        emission = sTex.a < 1.0 ? sTex.a : 0.0; // labPBR: 1.0 = none
    }
#endif

    vec4 albedo = texture2D(texture, uv) * glcolor;
    if (albedo.a < 0.1) discard;

    float mat = materialClass;
#ifdef TERRAIN
    if (matId == 10003.0) mat = 0.98;  // fully emissive blocks
    else if (matId == 10004.0) {
        // Ores: only the saturated/bright mineral specks glow, not the stone
        float mx = max(albedo.r, max(albedo.g, albedo.b));
        float mn = min(albedo.r, min(albedo.g, albedo.b));
        float speck = smoothstep(0.10, 0.32, mx - mn) * smoothstep(0.3, 0.55, mx);
        speck = max(speck, smoothstep(0.75, 0.95, mx) * 0.6); // pale gems (diamond/quartz)
        mat = max(mat, 0.855 + speck * 0.10);
    }
#endif
    if (emission > 0.02) mat = max(mat, 0.855 + emission * 0.125);

/* DRAWBUFFERS:015 */
    gl_FragData[0] = albedo;
    gl_FragData[1] = vec4(N * 0.5 + 0.5, mat);
    gl_FragData[2] = vec4(lmcoord, smoothness, f0);
}
#endif
