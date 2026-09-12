# 🎨 Dithering3D - Surface-Stable Fractal Dithering

![Minecraft](https://img.shields.io/badge/Minecraft-1.8.9_*_1.21%2B-62B47A?style=for-the-badge)
![OptiFine](https://img.shields.io/badge/OptiFine-All_Versions-2577D0?style=for-the-badge)
![Iris](https://img.shields.io/badge/Iris-1.2.0%2B-9B59B6?style=for-the-badge)
![License](https://img.shields.io/badge/License-MPL_2.0-E67E22?style=for-the-badge)

---

## 🖼️ Screenshots

![Dithering3D Preview](https://media.forgecdn.net/attachments/1454/997/2026-01-07_03-01-52-jpg.jpg)

---

## ✨ A Revolutionary Visual Experience

Transform your Minecraft world with **Surface-Stable Fractal Dithering** — a groundbreaking rendering technique where dither dots **stick to 3D surfaces** instead of the screen, creating a unique manga/comic book aesthetic that feels alive.

> 🎬 *Based on the innovative work by [Rune Skovbo Johansen](https://github.com/runevision/Dither3D)* — **[Watch the explainer video](https://youtu.be/HPqGaIMVuLs)**

---

## 🖼️ What Makes This Shader Special?

### 📌 **Surface-Stable Dots**
Unlike traditional dithering where patterns "swim" on screen, Dither3D anchors each dot to the actual 3D surface. Walk around blocks, and the dots stay perfectly attached!

### 🔄 **Fractal Scaling Magic**
As you move closer or farther from surfaces, dots dynamically split or merge to maintain **constant screen-space density**. It's mesmerizing to watch!

### 🎨 **Three Color Modes**

| Mode | Description |
|:----:|:------------|
| **Grayscale** | Classic black & white dithering — clean, minimalist, timeless |
| **RGB** | Each color channel gets its own dot layer — vibrant and unique |
| **CMYK Halftone** | Authentic newspaper/comic print simulation with rotated dot angles |

---

## ⚡ Features at a Glance

| Feature | Description |
|:--------|:------------|
| 🎯 **Precision Dithering** | SVD-based frequency analysis for mathematically perfect dot placement |
| 🌀 **Anti-Stretch Technology** | Anisotropic smoothing keeps dots circular even on oblique surfaces |
| 🎥 **Camera Stable** | Radial compensation prevents dot swimming during camera rotation |
| ⚙️ **Highly Configurable** | 10+ parameters to fine-tune your perfect look |
| 🚀 **Performance Optimized** | Efficient 3D texture sampling for smooth gameplay |
| 📱 **Universal Compatibility** | Works with OptiFine AND Iris on virtually any Minecraft version |

---

## 🎛️ Customization Options

Fine-tune every aspect of the dithering effect with our intuitive in-game sliders:

### 🔧 Dither Settings
| Parameter | Range | Effect |
|-----------|:-----:|--------|
| **Dot Scale** | 2 - 10 | Control overall dot size (exponential) |
| **Size Variability** | 0 - 1 | 0 = Bayer pattern, 1 = Halftone style |
| **Dot Contrast** | 0 - 2 | Sharpen or soften dot edges |
| **Stretch Smooth** | 0 - 2 | Combat stretched dots on angled surfaces |

### 💡 Input Controls
| Parameter | Range | Effect |
|-----------|:-----:|--------|
| **Exposure** | 0 - 5 | Brightness multiplier |
| **Offset** | -1 to 1 | Brightness offset adjustment |

### 🎮 Additional Options
- **Inverse Dots** — Flip dot colors for a negative effect
- **Radial Compensation** — Stabilize during camera rotation *(recommended!)*
- **Quantize Layers** — Prevent dot morphing for a more "classic" look
- **Debug Mode** — Visualize fractal layers for development

---

## 📦 Installation

### For OptiFine Users
1. Download and extract the shader pack
2. Place the `shaders` folder in `.minecraft/shaderpacks/`
3. Launch Minecraft → Options → Video Settings → Shaders
4. Select **Dithering3D** and enjoy!

### For Iris Users (Fabric/Quilt)
1. Install Iris Shaders mod (1.2.0+)
2. Download and extract the shader pack
3. Place the `shaders` folder in `.minecraft/shaderpacks/`
4. Press **O** in-game to open shader menu
5. Select **Dithering3D**

> 💡 **Tip:** Press `F3 + T` to quickly reload shaders after making changes!

---

## 🎨 Preset Profiles

Choose from pre-configured profiles for instant results:

| Profile | Color Mode | Dot Scale | Best For |
|:-------:|:----------:|:---------:|:---------|
| 🟢 **LOW** | Grayscale | 4.0 | Performance, retro feel |
| 🟡 **MEDIUM** | Grayscale | 5.0 | Balanced experience |
| 🟠 **HIGH** | RGB | 5.0 | Colorful, artistic |
| 🔴 **ULTRA** | CMYK | 6.0 | Maximum visual impact |

---

## 🌟 Perfect For

| 📸 Screenshot enthusiasts | Create unique, artistic captures |
|:------------------------:|:--------------------------------|
| 🎬 **Content creators** | Stand out with a distinctive visual style |
| 🎮 **Retro lovers** | Relive the charm of 1-bit graphics |
| 🎨 **Artists** | Manga, comic book, and newspaper aesthetics |
| 🧪 **Tech enthusiasts** | Experience cutting-edge rendering techniques |

---

## ❓ FAQ

**Q: Does this work with other shaders?**
> Dithering3D is a standalone shader pack. Combining with other shaders may cause conflicts.

**Q: Why do some surfaces look different?**
> The sky and some special effects may appear different as surface-stable dithering reveals flat geometry.

**Q: Performance impact?**
> Moderate. The 3D texture sampling is optimized but more demanding than vanilla rendering. Most GPUs handle it smoothly.

**Q: Can I use this in my modpack?**
> Yes! Under MPL-2.0 license. Credit appreciated.

---

## 🔬 The Science Behind It

Dithering3D uses **Singular Value Decomposition (SVD)** to analyze UV coordinate derivatives in real-time, determining the exact frequency and direction of surface textures. This mathematical approach enables:

```
✅ Perfectly uniform dot density regardless of distance
✅ Seamless fractal transitions between detail levels  
✅ Circular dots even on extremely angled surfaces
✅ Rotation-stable patterns that don't "swim"
```

---

## 📚 Credits & Resources

| Resource | Link |
|:---------|:-----|
| 🔗 **Original Algorithm** | [Rune Skovbo Johansen](https://github.com/runevision/Dither3D) |
| 🎥 **Technique Explanation** | [YouTube Video](https://youtu.be/HPqGaIMVuLs) |
| 💬 **Technical Discussion** | [FAQ Thread](https://github.com/runevision/Dither3D/discussions/12) |

---

## 📄 License

```
Mozilla Public License 2.0 (MPL-2.0)
```

---

<p align="center">
  <b>🎨 Transform your world. Experience Dithering3D. 🎨</b>
</p>

<p align="center">
  <i>If you enjoy this shader, consider leaving a ⭐ and sharing this shader page !</i>
</p>
