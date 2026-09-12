#include "/lib/all_the_libs.glsl"

// --- 0. SETTINGS ---
#define BUMP_STRENGTH  1.0

#define POM_DEPTH 0.01



/* RENDERTARGETS:0,8,9,7,11 */

// --- UNIFORMS ---
uniform sampler2D gtexture;

// --- VARYINGS ---
varying vec2 texcoord;
varying vec4 glcolor;
varying vec4 vTangent;
varying vec3 vViewPos;
varying vec2 LightmapCoords;
varying vec2 vMidCoord;
varying vec2 vTileSize;
varying vec3 ViewPos;

#define FLIP_X  1.0
#define FLIP_Y 1.0

#include "/global/lighting.fsh"
#include "/lib/distort.glsl"

// --- 1. SAFE WRAPPING FUNCTION ---
vec2 wrapCoord(vec2 coord) {
    vec2 offset = coord - vMidCoord;
    // Using 'fract' instead of 'mod' is much safer in GLSL for preventing texture tearing
    offset = (fract(offset / vTileSize + 0.5) - 0.5) * vTileSize;
    return vMidCoord + offset;
}


#ifdef POM
vec3 calculatePOM(vec2 coord, vec3 tangentViewDir, vec3 tangentLightDir) {
    // Apply the axis flip to correct the optical illusion
    tangentViewDir.xy *= vec2(FLIP_X, FLIP_Y);

    tangentViewDir.z = max(tangentViewDir.z, 0.001); 
    
    float numLayers = mix(MAX_STEPS, MIN_STEPS, tangentViewDir.z);
    float layerDepth = 1.0 / numLayers;
    float currentLayerDepth = 0.0;
    
    // This is the LearnOpenGL vector 'P'
    vec2 P = tangentViewDir.xy * POM_DEPTH / tangentViewDir.z; 
    vec2 deltaTexCoords = P / numLayers;
    
    vec2 currentTexCoords = coord;
    
    // Read the Height map and convert it to a LearnOpenGL Depth Map (1.0 - Height)
    float currentDepthMapValue = 1.0 - texture2DLod(normals, wrapCoord(currentTexCoords),0.0).a;

    currentLayerDepth += layerDepth;
    currentTexCoords -= deltaTexCoords;
    
    for(int i = 0; i < int(MAX_STEPS); i++) {
        if(currentLayerDepth >= currentDepthMapValue) break;
        
        currentTexCoords -= deltaTexCoords;
        currentDepthMapValue = 1.0 - texture2DLod(normals, wrapCoord(currentTexCoords),0.0).a;
        
        currentLayerDepth += layerDepth;
    }
    
    vec2 prevTexCoords = currentTexCoords + deltaTexCoords;
    float afterDepth  = currentDepthMapValue - currentLayerDepth;
    float beforeDepth = (1.0 - texture2DLod(normals, wrapCoord(prevTexCoords),0.0).a) - currentLayerDepth + layerDepth;
    
    float weight = clamp(afterDepth / max(afterDepth - beforeDepth,0.0001), 0.0, 1.0);
    vec2 finalCoords = prevTexCoords * weight + currentTexCoords * (1.0 - weight);
    
    // --- PARALLAX SELF-SHADOWING ---
    float shadow = 1.0;
    float finalLayerDepth = currentLayerDepth - layerDepth * (1.0 - weight);

    // Now, raymarch from the new surface point towards the light
    tangentLightDir.z = max(tangentLightDir.z, 0.001);
    vec2 lightDelta = -tangentLightDir.xy * POM_DEPTH / tangentLightDir.z;
    lightDelta /= numLayers;

    float lightLayerDepth = finalLayerDepth - layerDepth;
    vec2 lightTexCoords = finalCoords + lightDelta;

    for (int i = 0; i < int(MAX_STEPS / 2); i++) { // Shadow steps can be fewer
        if (lightLayerDepth < 0.0) break;

        float heightAtLightStep = 1.0 - texture2DLod(normals, wrapCoord(lightTexCoords), 0.0).a;
        if (lightLayerDepth > heightAtLightStep) {
            shadow = 0.4; // We are in shadow
            break;
        }
        lightTexCoords += lightDelta;
        lightLayerDepth -= layerDepth;
    }
    
    return vec3(wrapCoord(finalCoords), shadow);
}

#endif

void main() {
    // 1. SETUP COORDINATES & VIEW DIR
    vec3 viewDir = normalize(-vViewPos); // Point FROM the surface TO the camera

    // 2. FOOLPROOF TBN MATRIX (Screen-Space Derivatives)
    vec3 normalFace = normalize(Normal);
    
    // Look at how the geometry and UVs change per pixel
    vec3 dp1 = dFdx(vViewPos);
    vec3 dp2 = dFdy(vViewPos);
    vec2 duv1 = dFdx(texcoord);
    vec2 duv2 = dFdy(texcoord);

    // Calculate Tangent and Bitangent dynamically to perfectly match the texture
    vec3 dp2perp = cross(dp2, normalFace);
    vec3 dp1perp = cross(normalFace, dp1);
    vec3 T = dp2perp * duv1.x + dp1perp * duv2.x;
    vec3 B = dp2perp * duv1.y + dp1perp * duv2.y;

    // Build the matrix
    float invmax = inversesqrt(max(dot(T, T), dot(B, B)));
    mat3 TBN = mat3(T * invmax, B * invmax, normalFace);

    vec3 lightDir = normalize(sunPosition);
    vec3 tangentViewDir = normalize(viewDir * TBN);
    vec3 tangentLightDir = normalize(lightDir * TBN);

    vec2 newCoord = texcoord; // Default to standard coordinates
    float shadowMult = 1.0;
    #ifdef POM
        vec3 pomResult = calculatePOM(texcoord, tangentViewDir, tangentLightDir);
        newCoord = pomResult.xy;
        shadowMult = pomResult.z;
    #endif

    // 5. READ TEXTURES (Using newCoord!)
    vec4 color = texture2D(gtexture, newCoord) * glcolor;
    color.rgb = to_linear(color.rgb);
    vec3 albedo = color.rgb;

    // 6. NORMAL MAPPING

  
    

    vec3 normalMap = texture2D(normals, newCoord).xyz;
    normalMap = normalMap * 2.0 - 1.0; 
    normalMap.xy *= BUMP_STRENGTH; 

    float zSq = 1.0 - dot(normalMap.xy, normalMap.xy);
    if (zSq < 0.0) normalMap = normalize(vec3(normalMap.xy, 0.0)); 
    else normalMap.z = sqrt(zSq);
    
    vec3 finalNormal = normalize(TBN * normalMap);
    #ifdef RAIN_RIPPLES
    //apply ripples after all normals computed
    if (wetness > 0.01 && LightmapCoords.y > 0.7) {
        vec3 worldPos = to_player_pos(ViewPos) + cameraPosition;
        finalNormal = get_rain_ripple_normal(worldPos, finalNormal);
    }
    #endif
    

    // 5. SPECULAR (Read initial data using POM coords)
    vec4 specData = texture2D(specular, newCoord);
    float smoothness = specData.r;
    float f0 = specData.g;
    bool isMetal = f0 >= 0.9;

    // --- 4.5 WETNESS LOGIC (RAIN) ---
    if (wetness > 0.01) {
        float upAmount = max(0.0, dot(normalFace, vec3(0.0, 1.0, 0.0)));
        float wetFactor = wetness * upAmount * smoothstep(0.7, 0.9, LightmapCoords.y);

        albedo *= (1.0 - wetFactor * 0.4);
        smoothness = mix(smoothness, 0.95, wetFactor * 0.8);

        if (!isMetal) {
             f0 = mix(f0, 0.4, wetFactor); 
        }
    }

    // 6. LIGHTING
    // (Note: Reverting viewDir to your original logic for lighting reflections)
    vec3 lightViewDir = normalize(-vViewPos);
    if (length(sunPosition) < 0.1) lightDir = normalize(vec3(0.2, 1.0, 0.2));
    vec3 reflectDir = reflect(lightViewDir, finalNormal); 

    float NdotL = max(0.0, dot(finalNormal, lightDir));
    float NdotH = max(0.0, dot(reflectDir, lightDir));
    
    float specularStrength = pow(NdotH, 10.0 + (100.0 * smoothness)); 
    specularStrength *= smoothness * f0 * 5.0 * shadowMult; // Apply self-shadowing to specular

    vec3 worldPos = to_player_pos(ViewPos) + cameraPosition;

    // 7. COMBINE
    vec3 blockLight = tweak_lightmap(worldPos); 
    vec3 diffuse = isMetal ? color.rgb * 0.1 : albedo * blockLight;

    diffuse *= shadowMult; // Apply self-shadowing to diffuse light

    color.rgb = diffuse;

    // Output 
    gl_FragData[1] = vec4(smoothness, f0, 0.0, 1.0);
    gl_FragData[2] = vec4(finalNormal * 0.5 + 0.5, 1.0);
    gl_FragData[0] = color;
    gl_FragData[3] = vec4(albedo, 1.0);
    gl_FragData[4] = vec4(0.0, 0.0, 0.0, 1.0); // Placeholder for future use
}