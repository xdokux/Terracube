
Ce document regroupe des palettes optimisées pour le post-processing et le dithering. Elles sont classées par style.

> **Note technique pour GLSL :** Les valeurs RGB sont normalisées (entre 0.0 et 1.0).
> Format : `vec3(R, G, B)`

---

## 1. Les "Must-Have" (Rétro & Classique)
*Ces palettes sont légendaires pour le dithering car elles sont conçues pour des systèmes à mémoire limitée.*

### A. Game Boy (4 Couleurs)
**Ambiance :** Nostalgique, verte, très lisible.
**Pourquoi :** Le dithering fonctionne parfaitement car la rampe de luminosité est linéaire.

| Nom | Hex | GLSL vec3 |
| :--- | :--- | :--- |
| Blackish | `#0f380f` | `vec3(0.06, 0.22, 0.06)` |
| Dark Green | `#306230` | `vec3(0.19, 0.38, 0.19)` |
| Light Green | `#8bac0f` | `vec3(0.55, 0.67, 0.06)` |
| Whiteish | `#9bbc0f` | `vec3(0.61, 0.74, 0.06)` |

### B. CGA Palette 1 High (4 Couleurs)
**Ambiance :** Cyber-rétro, agressif, néon.
**Pourquoi :** Le cyan et le magenta créent un dithering très texturé et reconnaissable entre mille.

| Nom | Hex | GLSL vec3 |
| :--- | :--- | :--- |
| Black | `#000000` | `vec3(0.0, 0.0, 0.0)` |
| Cyan | `#55ffff` | `vec3(0.33, 1.0, 1.0)` |
| Magenta | `#ff55ff` | `vec3(1.0, 0.33, 1.0)` |
| White | `#ffffff` | `vec3(1.0, 1.0, 1.0)` |

### C. Pico-8 (16 Couleurs)
**Ambiance :** Fantaisie, vibrant, équilibré.
**Pourquoi :** C'est sans doute la meilleure palette 16 couleurs jamais créée. Elle couvre tout le spectre nécessaire pour Minecraft sans être terne.



*Sélection des couleurs clés (pour tableau GLSL complet, voir spécifications Pico-8)* :
```glsl
vec3[] pico8 = vec3[](
    vec3(0.00, 0.00, 0.00), // Black
    vec3(0.11, 0.17, 0.33), // Dark Blue
    vec3(0.49, 0.15, 0.20), // Dark Purple
    vec3(0.00, 0.53, 0.32), // Dark Green
    vec3(0.67, 0.32, 0.21), // Brown
    vec3(0.37, 0.34, 0.31), // Dark Grey
    vec3(0.76, 0.76, 0.78), // Light Grey
    vec3(1.00, 0.95, 0.91), // White
    vec3(1.00, 0.00, 0.30), // Red
    vec3(1.00, 0.64, 0.00), // Orange
    vec3(1.00, 0.93, 0.15), // Yellow
    vec3(0.00, 0.89, 0.21), // Green
    vec3(0.16, 0.68, 1.00), // Blue
    vec3(0.51, 0.46, 0.61), // Indigo
    vec3(1.00, 0.47, 0.66), // Pink
    vec3(1.00, 0.80, 0.67)  // Peach
);

```

---

## 2. Les "Jolies" (Esthétique & Doux)

*Pour un rendu agréable à l'œil, moins agressif que le rétro pur.*

### A. Nord Theme (16 Couleurs)

**Ambiance :** Froid, polaire, moderne, apaisant.
**Pourquoi :** Très populaire chez les développeurs, donne un aspect "glacé" magnifique aux paysages de Minecraft.

*Extrait des couleurs principales (Frost & Aurora)* :

```glsl
vec3[] nord = vec3[](
    vec3(0.18, 0.20, 0.25), // Dark Grey
    vec3(0.85, 0.87, 0.91), // Snow White
    vec3(0.56, 0.74, 0.73), // Frost Cyan
    vec3(0.37, 0.51, 0.67), // Frost Blue
    vec3(0.75, 0.38, 0.45), // Red
    vec3(0.81, 0.55, 0.43), // Orange
    vec3(0.92, 0.79, 0.54), // Yellow
    vec3(0.64, 0.75, 0.55)  // Green
);

```

### B. Solarized Dark (Base 8)

**Ambiance :** Faible contraste, tons chauds/cyans.
**Pourquoi :** Réduit la fatigue oculaire. Excellent pour un shader de nuit ou "chill exploration".

| Nom | Hex | GLSL vec3 |
| --- | --- | --- |
| Base03 | `#002b36` | `vec3(0.0, 0.17, 0.21)` |
| Base01 | `#586e75` | `vec3(0.35, 0.43, 0.46)` |
| Cyan | `#2aa198` | `vec3(0.16, 0.63, 0.60)` |
| Orange | `#cb4b16` | `vec3(0.80, 0.29, 0.09)` |

---

## 3. Les Originales & Artistiques

*Pour changer radicalement l'ambiance du jeu.*

### A. 1-Bit (Monochrome)

**Ambiance :** Encre, Manga, Sin City.
**Pourquoi :** C'est le test ultime du dithering. Ne fonctionne que si ton algorithme de matrice (Bayer ou Blue Noise) est bon.

| Nom | Hex | GLSL vec3 |
| --- | --- | --- |
| Black | `#000000` | `vec3(0.0, 0.0, 0.0)` |
| White | `#ffffff` | `vec3(1.0, 1.0, 1.0)` |

### B. Virtual Boy (Rouge & Noir)

**Ambiance :** Cauchemardesque, enfer, technologique.
**Pourquoi :** Très original pour des dimensions comme le Nether.

| Nom | Hex | GLSL vec3 |
| --- | --- | --- |
| Black | `#000000` | `vec3(0.0, 0.0, 0.0)` |
| Dark Red | `#550000` | `vec3(0.33, 0.0, 0.0)` |
| Med Red | `#aa0000` | `vec3(0.66, 0.0, 0.0)` |
| Bright Red | `#ff0000` | `vec3(1.0, 0.0, 0.0)` |

### C. Sepia (Old Photo)

**Ambiance :** Western, Flashback, Histoire.

| Nom | Hex | GLSL vec3 |
| --- | --- | --- |
| Dark Brown | `#2b1d0e` | `vec3(0.17, 0.11, 0.05)` |
| Mid Brown | `#704214` | `vec3(0.44, 0.26, 0.08)` |
| Paper | `#d2b48c` | `vec3(0.82, 0.71, 0.55)` |
| Fade | `#f5deb3` | `vec3(0.96, 0.87, 0.70)` |

# Palette Spéciale : "Dark Fantasy" (16 Couleurs)

Cette palette est conçue spécifiquement pour Minecraft avec des teintes sombres évoquant un monde ancien et corrompu.

### Pourquoi elle fonctionne en Dithering :
* **Ombres riches :** Les noirs tirent vers le violet/bleu nuit, donnant de la profondeur aux zones sombres.
* **Gamme complète :** 16 couleurs couvrent tous les besoins : pierre, bois, végétation, eau, feu, magie.
* **Mapping Minecraft :** Chaque couleur correspond à des éléments du jeu.

### La Palette "Dark Fantasy" (16 Couleurs)

| # | Hex | Nom | Rôle Minecraft |
|---|-----|-----|----------------|
| 1 | `#05040b` | Noir Abyssal | Vide, ciel End, ombres totales |
| 2 | `#1a1624` | Obsidienne Maudite | Deepslate, grottes, blocs noirs |
| 3 | `#2f2a3e` | Gris Ardoise | Pierre dans l'ombre |
| 4 | `#464255` | Fer Ancien | Pierre éclairée, fer, outils |
| 5 | `#6e7278` | Gris Cendre | Argile, pierre très éclairée |
| 6 | `#d4d3cf` | Os Blanchi | Neige, quartz, squelettes |
| 7 | `#382d26` | Boue Séchée | Terre sombre, écorce |
| 8 | `#785640` | Bois de Cercueil | Planches, coffres, cuir |
| 9 | `#421216` | Sang Coagulé | Netherrack, Redstone |
| 10 | `#b55231` | Rouille | Cuivre, Acacia, briques |
| 11 | `#e0a64e` | Or Fiévreux | Torches, soleil, lave |
| 12 | `#1e291f` | Marécage Sombre | Feuilles, marais |
| 13 | `#334d38` | Mousse Toxique | Herbe, Slimes, Creepers |
| 14 | `#131e2e` | Fosse Marine | Eau profonde, ciel nocturne |
| 15 | `#5b7a9e` | Acier Lunaire | Eau, glace, diamant |
| 16 | `#4d265e` | Décomposition Royale | Magie, Endermen, portails |

### Implémentation GLSL (triée par luminance)

```glsl
// Palette Dark Fantasy - 16 Couleurs (triée par luminance)
vec3 getPaletteEldritch(int index) {
    if (index == 0)  return vec3(0.020, 0.016, 0.043);  // Noir Abyssal
    if (index == 1)  return vec3(0.102, 0.086, 0.141);  // Obsidienne Maudite
    if (index == 2)  return vec3(0.075, 0.118, 0.180);  // Fosse Marine
    if (index == 3)  return vec3(0.259, 0.071, 0.086);  // Sang Coagulé
    if (index == 4)  return vec3(0.118, 0.161, 0.122);  // Marécage Sombre
    if (index == 5)  return vec3(0.184, 0.165, 0.243);  // Gris Ardoise
    if (index == 6)  return vec3(0.220, 0.176, 0.149);  // Boue Séchée
    if (index == 7)  return vec3(0.302, 0.149, 0.369);  // Décomposition Royale
    if (index == 8)  return vec3(0.200, 0.302, 0.220);  // Mousse Toxique
    if (index == 9)  return vec3(0.275, 0.259, 0.333);  // Fer Ancien
    if (index == 10) return vec3(0.471, 0.337, 0.251);  // Bois de Cercueil
    if (index == 11) return vec3(0.710, 0.322, 0.192);  // Rouille
    if (index == 12) return vec3(0.431, 0.447, 0.471);  // Gris Cendre
    if (index == 13) return vec3(0.357, 0.478, 0.620);  // Acier Lunaire
    if (index == 14) return vec3(0.878, 0.651, 0.306);  // Or Fiévreux
    return vec3(0.831, 0.827, 0.812);                    // Os Blanchi
}