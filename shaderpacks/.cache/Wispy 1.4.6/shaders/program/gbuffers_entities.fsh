#include "/lib/all_the_libs.glsl"
uniform sampler2D gtexture;
varying vec2 texcoord;
varying vec4 glcolor;
#include "/global/lighting.fsh"
void main() {
    vec4 Color = texture2D(gtexture, texcoord) * glcolor;
    Color.rgb = to_linear(Color.rgb);
    if (entityId == 10001) {
        Color.a = 1.0;
    }
    else {
        Color.rgb = mix(Color.rgb, entityColor.rgb, entityColor.a);
        Color.rgb *= MixedLights;
    }
    Color.a = max(Color.a, 0.01);
    if (Color.a < 0.1) {
        discard;
    }
    gl_FragData[0] = Color;
}
