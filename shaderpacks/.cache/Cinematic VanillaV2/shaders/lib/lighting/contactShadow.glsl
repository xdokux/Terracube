// ============================================================
//  CinematicVanilla V2 - contactShadow.glsl   (NEW in V2)
//  Screen-space contact shadow / ambient occlusion darkening
//  at geometry boundaries. Very cheap: no shadow map needed.
//  Include from composite.fsh and apply as a darkness factor.
// ============================================================

#ifdef CONTACT_SHADOWS

// Returns a [0..1] darkness factor.
// 0 = fully in contact shadow, 1 = fully lit.
// screenPos: reconstructed view-space position
// normal:    surface normal in view space
// depthtex0: bound to sampler2D depthtex0
float getContactShadow(in vec3 screenPos, in vec3 normal){
    // March along the surface-tangent toward the light
    // We approximate using a short screen-space ray toward the sun.
    // For performance, CONTACT_SHADOW_STEPS should be ≤ 16 on MEDIUM.

    // Project surface-offset direction into screen space
    vec3 rayDir = normalize(normal + vec3(0.0, 1.0, 0.0));
    float stepSize = CONTACT_SHADOW_RADIUS / float(CONTACT_SHADOW_STEPS);

    float occlusion = 0.0;
    vec3  samplePos = screenPos;

    for(int i = 0; i < CONTACT_SHADOW_STEPS; i++){
        samplePos += rayDir * stepSize;

        // Project to screen UV
        vec4 proj = gbufferProjection * vec4(samplePos, 1.0);
        proj.xyz /= proj.w;
        vec2 sUV = proj.xy * 0.5 + 0.5;

        if(sUV.x < 0.0 || sUV.x > 1.0 || sUV.y < 0.0 || sUV.y > 1.0) break;

        float sampledDepth = texture(depthtex0, sUV).r;
        // Reconstruct view-space Z from depth
        vec4 sDepthView = gbufferProjectionInverse * vec4(sUV * 2.0 - 1.0, sampledDepth * 2.0 - 1.0, 1.0);
        sDepthView.xyz /= sDepthView.w;

        float depthDiff = samplePos.z - sDepthView.z;
        if(depthDiff > 0.02 && depthDiff < 0.5){
            // Fade occlusion based on march progress
            float weight = 1.0 - float(i) / float(CONTACT_SHADOW_STEPS);
            occlusion = max(occlusion, weight);
        }
    }

    // Return 1 where lit, 0 where shadowed
    return 1.0 - occlusion * 0.65;
}

#endif // CONTACT_SHADOWS
