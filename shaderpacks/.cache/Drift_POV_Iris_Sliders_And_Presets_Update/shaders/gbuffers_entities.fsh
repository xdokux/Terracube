#version 120
uniform sampler2D texture;
uniform vec4 entityColor; // This is the secret for the Red Damage Flash!

varying vec2 texcoord;
varying vec4 glcolor;

void main() {
    vec4 color = texture2D(texture, texcoord) * glcolor;
    
    // Mix the base texture with the red damage tint
    color.rgb = mix(color.rgb, entityColor.rgb, entityColor.a);
    
    gl_FragData[0] = color;
}