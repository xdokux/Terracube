vec3 project_and_divide(mat4 Projection_mat, vec3 x) {
    vec4 HomogeneousPos = Projection_mat * vec4(x, 1);
    return HomogeneousPos.xyz / HomogeneousPos.w;
}

vec3 screen_view(vec3 x, bool IsDH, const bool ShouldUnjitter) {
    x = x * 2 - 1;

    if(ShouldUnjitter)
    x.xy -= taaJitter;

    mat4 ProjMat = IsDH ? dhProjectionInverse : gbufferProjectionInverse;
    return project_and_divide(ProjMat, x);
}

vec3 view_player(vec3 x, bool IsDH) {
    #ifdef VOXY
        mat4 Mat = IsDH ? vxModelViewInv : gbufferModelViewInverse;
    #else
        mat4 Mat = gbufferModelViewInverse;
    #endif
    return mat3(Mat) * x;
}

vec3 player_view(vec3 x, bool IsDH) {
    #ifdef VOXY
        mat4 Mat = IsDH ? vxModelView : gbufferModelView;
    #else
        mat4 Mat = gbufferModelView;
    #endif
    return mat3(Mat) * x;
}


vec3 view_screen(vec3 x, bool IsDH, const bool ShouldJitter) {
    mat4 ProjMat = IsDH ? dhProjection : gbufferProjection;
    x = project_and_divide(ProjMat, x);

    if(ShouldJitter)
        x.xy += taaJitter;

    x = x * 0.5 + 0.5;
    return x;
}

struct Positions {
    vec3 Screen, View, Player, ViewN, PlayerN, World;
};

Positions get_positions(vec2 texcoord, float Depth, bool IsDH, const bool ShouldJitter) {
    Positions Pos;
    Pos.Screen = vec3(texcoord, Depth);
    Pos.View = screen_view(Pos.Screen, IsDH, ShouldJitter);
    Pos.Player = view_player(Pos.View, IsDH);
    Pos.ViewN = normalize(Pos.View);
    Pos.PlayerN = normalize(Pos.Player);
    Pos.World = Pos.Player + cameraPosition;
    return Pos;
}

vec3 player_shadow(vec3 PlayerPos) {
    vec3 ShadowPos = project_and_divide(shadowProjection, (shadowModelView * vec4(PlayerPos + gbufferModelViewInverse[3].xyz, 1)).xyz); //convert to shadow ndc space
    return ShadowPos;
}

// In shaderlabs discord: https://discord.com/channels/237199950235041794/525510804494221312/955506913834070016
vec2 toPrevScreenPos(vec2 currScreenPos, float depth, bool isDH, bool ShouldUnjitter) {
    mat4 ProjInv = isDH ? dhProjectionInverse : gbufferProjectionInverse;
    mat4 PrevProj = isDH ? dhPreviousProjection : gbufferPreviousProjection;
    #ifdef VOXY
        mat4 ModelViewInv = isDH ? vxModelViewInv : gbufferModelViewInverse;
        mat4 PrevModelView = isDH ? vxModelViewPrev : gbufferPreviousModelView;
    #else
        mat4 ModelViewInv = gbufferModelViewInverse;
        mat4 PrevModelView = gbufferPreviousModelView;
    #endif
    currScreenPos.xy = currScreenPos.xy * 2.0 - 1.0;
    if(ShouldUnjitter) currScreenPos.xy += taaJitter;
    vec3 currViewPos = vec3(vec2(ProjInv[0].x, ProjInv[1].y) * (currScreenPos.xy) + ProjInv[3].xy, ProjInv[3].z);
    currViewPos /= (ProjInv[2].w * (depth * 2.0 - 1.0) + ProjInv[3].w);
    vec3 currFeetPlayerPos = mat3(ModelViewInv) * currViewPos + ModelViewInv[3].xyz;

    vec3 prevFeetPlayerPos = depth > 0.56 ? currFeetPlayerPos + cameraPosition - previousCameraPosition : currFeetPlayerPos;
    vec3 prevViewPos = mat3(PrevModelView) * prevFeetPlayerPos + PrevModelView[3].xyz;
    vec2 finalPos = vec2(PrevProj[0].x, PrevProj[1].y) * prevViewPos.xy + PrevProj[3].xy;
    finalPos /= -prevViewPos.z;
    if(ShouldUnjitter) finalPos.xy -= taaJitter;
    return finalPos * 0.5 + 0.5;
}

#define linear_srgb(linear) ( mix(12.92 * linear, 1.055 * pow(linear, vec3(1/2.4)) - 0.055, step(0.0031308, linear)) )

#define srgb_linear(srgb) ( mix(srgb / 12.92, pow(((srgb + 0.055)/(1.055)), vec3(2.4)), step(0.04045, srgb)))

// https://graphicrants.blogspot.com/2009/04/rgbm-color-encoding.html
vec4 RGBMEncode( vec3 color ) {
    vec4 rgbm;
    color = sqrt(color);
    color *= 1.0 / 6.0;
    rgbm.a = clamp( max( max( color.r, color.g ), max( color.b, 1e-6 ) ), 0, 1 );
    rgbm.a = ceil( rgbm.a * 255.0 ) / 255.0;
    rgbm.rgb = color / rgbm.a;
    return rgbm;
}

vec3 RGBMDecode( vec4 rgbm ) {
    return pow2(6.0 * rgbm.rgb * rgbm.a);
}

vec3 texture_rgbm(sampler2D sampler, vec2 texcoord) {
    return RGBMDecode(texture(sampler, texcoord));
}

vec4 RGBMEncode_srgb( vec3 color ) {
    vec4 rgbm;
    color *= 1.0 / 6.0;
    rgbm.a = clamp( max( max( color.r, color.g ), max( color.b, 1e-6 ) ), 0, 1 );
    rgbm.a = ceil( rgbm.a * 255.0 ) / 255.0;
    rgbm.rgb = color / rgbm.a;
    return rgbm;
}

vec3 RGBMDecode_srgb( vec4 rgbm ) {
    return 6.0 * rgbm.rgb * rgbm.a;
}

vec3 texture_rgbm_srgb(sampler2D sampler, vec2 texcoord) {
    return RGBMDecode_srgb(texture(sampler, texcoord));
}