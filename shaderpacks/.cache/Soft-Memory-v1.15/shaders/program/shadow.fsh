/* DRAWBUFFERS:0 */
uniform sampler2D tex;

varying vec4 color;
varying vec2 texcoord;
flat varying float blockID;

void main() {
    vec4 textureColor = vec4(texture2D(tex,texcoord.xy).rgb * color.rgb, texture2DLod(tex, texcoord.xy, 0).a);
    
    if (textureColor.a < 0.1) discard;
    
    gl_FragData[0] = textureColor;

}