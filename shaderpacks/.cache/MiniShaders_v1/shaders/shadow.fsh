#version 120

// GamesofDev is non chalant
varying vec2 texcoord;
varying vec4 glColor;
varying float blockId;

uniform sampler2D texture;

/* DRAWBUFFERS:01 */

void main() {
    vec4 color = texture2D(texture, texcoord) * glColor;
    bool isStainedGlass = abs(blockId - 10021.0) < 0.5;
    bool isRegularGlass = abs(blockId - 10020.0) < 0.5;
    bool isIce = abs(blockId - 10022.0) < 0.5;
    bool isTransparentBlock = isStainedGlass || isRegularGlass || isIce;
    
    if (!isTransparentBlock && color.a < 0.1) discard;
    
    // For transparent blocks: don't discard — let shadow map record them
    // This enables dual-depth shadow mapping (shadowtex0 vs shadowtex1)
    
    // Output depth (buffer 0 — written to shadowtex0 with alpha test)
    gl_FragData[0] = vec4(color.rgb, color.a);
    
    // Output colored shadow data (buffer 1 — shadowcolor0)
    if (isStainedGlass) {
        // Stained glass: gamma-corrected color for vivid colored shadows
        // pow(0.45) gamma boosts saturation, making colored light through glass more vivid
        vec3 tint = pow(color.rgb, vec3(0.45)) * 1.3;
        gl_FragData[1] = vec4(tint, color.a);
    } else if (isRegularGlass) {
        // Regular glass: mostly transparent, slight dimming
        gl_FragData[1] = vec4(0.95, 0.95, 0.95, color.a * 0.15);
    } else if (isIce) {
        // Ice: slight blue tint in shadow
        gl_FragData[1] = vec4(0.85, 0.92, 1.0, color.a * 0.4);
    } else {
        // Opaque blocks: full shadow, no color tint
        gl_FragData[1] = vec4(1.0, 1.0, 1.0, 1.0);
    }
}
