# Dither3D Shader - Installation Guide

## Prerequisites

### Required
- **Minecraft Java Edition**
  - Minecraft 1.8.9 - 1.21.x (all versions supported)
  - Best experience on 1.16.5+ (better shader support)

- **OptiFine** OR **Iris Shaders** mod:
  - **OptiFine HD U** (any version)
    - Download: https://optifine.net/downloads
    - Compatible: Minecraft 1.8+ to 1.21.x
    - Standalone or with Forge
  
  - **Iris Shaders 1.2.0+**
    - Download: https://irisshaders.net/
    - Compatible: Minecraft 1.16.5+ to 1.21.x
    - Requires Fabric/Quilt loader
    - Recommended for best performance

### Optional
- **Text editor with GLSL support** (for customization)

---

## Installation Methods

### Method 1: Automatic (Windows PowerShell)

1. Open PowerShell in the project directory
2. Run the build script:
   ```powershell
   .\build.ps1
   ```
3. Follow the on-screen instructions

The script will:
- Validate shader files
- Copy files to `.minecraft/shaderpacks/Dither3D/`
- Display next steps

**Note:** This shader uses procedural generation - no texture files needed!

---

### Method 2: Manual Installation

#### Step 1: Copy Shader Files
Copy the entire `shaders/` directory to:
```
%APPDATA%\.minecraft\shaderpacks\Dither3D\
```

**Mac:**
```
~/Library/Application Support/minecraft/shaderpacks/Dither3D/
```

**Linux:**
```
~/.minecraft/shaderpacks/Dither3D/
```

#### Step 2: Enable in Minecraft
1. Launch Minecraft
2. Go to **Options → Video Settings → Shaders**
3. Select **Dither3D** from the list
4. Click **Done**

---

## Verification

### Check Shader Load
1. Press **F3** in Minecraft to open debug overlay
2. Look for errors in top-right (shader errors shown in red)
3. Check console logs: `%APPDATA%\.minecraft\logs\latest.log`

### Expected Behavior
- Blocks/terrain should have dithered appearance
- Dots should stick to surfaces (move your camera to verify)
- Sky should use spherical dithering (not flat)

### Troubleshooting

**Problem:** White/missing textures
- **Cause:** Texture files not found or wrong format
- **Fix:** Check `textures/` directory, verify `.raw` or `.png` files exist
- **Alternative:** Enable `PROCEDURAL_TEXTURES` in config

**Problem:** Shader compile errors (`[Shaders] Error linking program`)
- **Cause:** GLSL syntax issues or missing includes
- **Fix:** Check `logs/latest.log` for specific file/line number
- **Common issues:**
  - `#include` paths (must be relative to `shaders/`)
  - Uniform name mismatches
  - Texture sampler type mismatch

**Problem:** Dots don't stick to surfaces
- **Cause:** Wrong UV coordinates used
- **Fix:** Ensure `texcoord` (not `gl_TexCoord[0]`) is passed to dither function

**Problem:** Performance issues
- **Cause:** Complex fractal layer calculations
- **Fix:** Use shader options menu (Esc → Options → Video Settings → Shaders → Shader Options)
  - Lower `Dot Scale` (reduces calculations)
  - Set `Performance` profile to `LOW` or `MEDIUM`
  - Disable `Debug Fractal` mode

---

##All patterns are generated procedurally in real-time

### Troubleshootine mode, Inverse Dots ON
- **Fast:** `LOW` profile, Dot Scale 3, Grayscale mode

### Manual Tweaks
| Parameter | Effect | Tip |
|-----------|--------|-----|
| **Dot Scale** | Size of dither dots | 5-7 for realism, 3-4 for speed |
| **Color Mode** | Grayscale/RGB/CMYK | CMYK = halftone printing effect |
| **Size Variability** | Dot uniformity | 0 = consistent, 1 = random sizes |
| **Contrast** | Dot edge sharpness | 1.5+ for comic book style |
| **Inverse Dots** | Flip colors | Creates negative effect |

---

## Development Workflow

### Hot-Reload Shaders
Press **F3+T** to reload shaders without restarting Minecraft. Useful for live editing.

### File Watching (Linux/Mac)
Auto-copy on file change:
```bash
# Watch for changes and auto-deploy
fswatch -o shaders/ | xargs -n1 -I{} cp -r shaders/ ~/.minecraft/shaderpacks/Dither3D/
```

### Debugging Tips
1. **Visualize intermediate values:** Output to `gl_FragColor` directly
   ```glsl
   gl_FragColor = vec4(vec3(frequency), 1.0);  // View frequency map
   ```
2. **Disable dithering temporarily:** Comment out `applyDither3DColor()` call
3. **Check per-channel:** Output single color channel
   ```glsl
   float c = ditherCMYK(...).r;  // Cyan channel only
   gl_FragColor = vec4(c, c, c, 1.0);
   ```

---

## Uninstallation

1. Open Minecraft shader selection menu
2. Select **(internal)** or any other shader
3. Delete `%APPDATA%\.minecraft\shaderpacks\Dither3D\`

---

## Next Steps
echnical docs:** `docs/TECHNICAL.md` (algorithm details)
- **Check compatibility:** `docs/COMPATIBILITY.md` (version info behavior)
- **Run tests:** `python tests/test_math.py` (verify math functions)
- **Customize:** Edit `shaders/lib/dither3d_config.glsl` for advanced tuning
- **Report issues:** https://github.com/[your-repo]/issues

---

## License

This shader is a derivative work of [Dither3D by Rune Skovbo Johansen](https://github.com/runevision/Dither3D), licensed under **MPL-2.0**.

Changes made to original files must be documented (see headers in `.glsl` files).
