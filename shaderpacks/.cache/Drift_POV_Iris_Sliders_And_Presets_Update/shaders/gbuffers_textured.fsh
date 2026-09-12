#version 120

uniform sampler2D texture;

varying vec2 texcoord;
varying vec4 glcolor;

void main() {
    // Multiplies the block texture by the game's lighting
    vec4 color = texture2D(texture, texcoord) * glcolor;
    
    // Sends the final image to the composite shader
    gl_FragData[0] = color;
}