#ifndef COMMON_GLSL
#define COMMON_GLSL

/* =====================================================================
   common.glsl  —  Ajustes globales y constantes compartidas.
   OptiFine/Iris leen los comentarios // [..] como opciones del menú.
   ===================================================================== */

// ---------- Calidad / Rendimiento (iGPU AMD 610M) ----------
#define SHADOW_SAMPLES 4        // [1 2 4 8] muestras PCF
#define SHADOW_SOFTNESS 1.0     // [0.5 1.0 1.5 2.0] radio de penumbra
#define SSR_STEPS 16            // [8 12 16 24 32] pasos del raymarch de reflejos
#define GODRAY_SAMPLES 12       // [4 6 8 12 16] muestras de luz volumétrica
#define POM_LAYERS 16           // [0 8 16 24 32] 0 = POM desactivado
#define POM_DEPTH 0.20          // [0.05 0.10 0.20 0.35] profundidad del relieve
#define FXAA 1                  // [0 1] antialiasing barato (suaviza dientes de sierra)

// Mapa de sombras. Consts aquí (no en shaders.properties) para que los
// PERFILES del menú puedan cambiarlas.
const int   shadowMapResolution = 1536;   // [1024 1536 2048 3072]
const float shadowDistance      = 96.0;   // [64.0 96.0 128.0]

// ---------- Clima (lluvia) ----------
#define WET_EFFECTS 1           // [0 1] los bloques se oscurecen/brillan mojados
#define PUDDLES 1               // [0 1] charcos al llover (en suelo a cielo abierto)
#define PUDDLE_AMOUNT 0.55      // [0.35 0.55 0.75] cantidad de charcos
#define RAIN_RIPPLES 1          // [0 1] gotas ondulando la superficie del agua
#define CLOUD_SHADOWS 1         // [0 1] sombras de las nubes sobre el terreno
#define CLOUD_SHADOW_STRENGTH 0.55 // [0.30 0.55 0.80] oscuridad de esas sombras
#define RAINBOW 1               // [0 1] arcoíris al escampar (tras la lluvia)
#define RAINBOW_STRENGTH 0.6    // [0.3 0.6 1.0] brillo del arcoíris
#define LIGHTNING_FLASH 1       // [0 1] los relámpagos iluminan cielo y terreno (Iris)

// ---------- Agua 2.0 ----------
#define CAUSTICS 1              // [0 1] dibujos de luz en el fondo del agua
#define CAUSTICS_STRENGTH 0.8   // [0.4 0.8 1.2] intensidad de las cáusticas
#define REFRACTION 1            // [0 1] el fondo se deforma al mirar a través del agua
#define REFRACTION_STRENGTH 1.0 // [0.5 1.0 1.5] fuerza de la refracción
#define FOAM 1                  // [0 1] espuma en orillas y bordes

// ---------- Luz dinámica en mano ----------
#define HANDLIGHT 1             // [0 1] antorcha/lámpara en mano ilumina alrededor
#define HANDLIGHT_STRENGTH 1.0  // [0.5 1.0 1.5] fuerza de la luz en mano

// ---------- Cielo extra ----------
#define STAR_TWINKLE 1          // [0 1] las estrellas titilan

// ---------- Iluminación ----------
#define SUN_BRIGHTNESS 1.05     // [0.6 0.8 1.05 1.3 1.6] intensidad del sol (de día)
#define NIGHT_BRIGHTNESS 1.0    // [0.5 0.75 1.0 1.5 2.0] brillo de la noche (sube si es muy oscura)
#define INTERIOR_DARKEN 0.40    // [0.20 0.30 0.40 0.55 0.70 1.0] oscurece interiores/sombra (1.0 = off)
#define GODRAY_STRENGTH 0.30    // [0.0 0.15 0.30 0.50 0.80] intensidad de los rayos de luz

// ---------- Cielo / Nubes / Estrellas ----------
#define CLOUDS 1                // [0 1] nubes procedurales
#define CLOUD_COVERAGE 0.50     // [0.30 0.40 0.50 0.65] cobertura de nubes
#define CLOUD_SPEED 1.0         // [0.5 1.0 1.5 2.0] velocidad del viento de nubes
#define GALAXY 1                // [0 1] vía láctea / galaxia
#define GALAXY_STRENGTH 1.0     // [0.5 1.0 1.5 2.0] brillo de la galaxia
#define STAR_AMOUNT 1.0         // [0.6 1.0 1.4 1.8] densidad de estrellas
#define STAR_BRIGHTNESS 0.55    // [0.25 0.55 0.80 1.0] brillo de estrellas
#define SHOOTING_STARS 1        // [0 1] estrellas fugaces ocasionales
#define MOON_SIZE 0.046         // tamaño angular de la luna (radianes) redonda
#define SUN_SIZE  0.046         // tamaño angular del sol (radianes) redondo

// ---------- Niebla atmosférica (horizonte) ----------
#define FOG_DENSITY 0.70        // [0.0 0.35 0.55 0.70 1.0] niebla SOLO en el borde lejano (0 = todo nítido)
#define NETHER_FOG 0.25         // [0.0 0.25 0.5 0.75 1.0] niebla del Nether (0 = nítido total; sube para profundidad)
#define END_BRIGHTNESS 1.10     // [0.8 1.0 1.1 1.3 1.6] brillo del terreno del End

// ---------- Viento (vegetación) ----------
#define WAVING 1                // [0 1] hojas y plantas al viento
#define WAVE_SPEED 1.0          // [0.5 1.0 1.5 2.0]
#define WAVE_STRENGTH 1.0       // [0.5 1.0 1.5 2.0]

// ---------- Color (look final) ----------
#define EXPOSURE 0.85           // [0.60 0.70 0.85 1.00 1.15] exposición global (baja si todo se ve blanco)
#define SATURATION 0.90         // [0.70 0.80 0.90 1.00 1.10] <1 = menos saturado (más natural)
#define CONTRAST 1.05           // [1.00 1.05 1.10 1.15] contraste

// ---------- Bloom (resplandor de lava / lámparas / sol) ----------
#define BLOOM 1                 // [0 1] resplandor (0 = off, más FPS)
#define BLOOM_STRENGTH 0.55     // [0.0 0.25 0.45 0.55 0.70 1.0] intensidad del resplandor
#define BLOOM_SPREAD 3.2        // [1.5 2.0 2.5 3.2 4.0 5.0] amplitud del resplandor (sube = se esparce más)
#define BLOOM_THRESHOLD 1.0     // [0.5 0.8 1.0 1.5] umbral (qué tan brillante para brillar)

// ---------- Agua ----------
#define WATER_WAVE_HEIGHT 0.06  // [0.02 0.04 0.06 0.10] amplitud del oleaje
#define WATER_WAVE_SPEED 1.0    // [0.5 1.0 1.5 2.0] velocidad del oleaje
#define WATER_FOG_DENSITY 0.55  // [0.20 0.35 0.55 0.80] densidad del agua desde fuera
#define UNDERWATER_DENSITY 0.35 // [0.10 0.20 0.35 0.60] niebla al estar SUMERGIDO

// ---------- Lava ----------
#define LAVA_FLOW_SPEED 0.18       // [0.08 0.12 0.18 0.25] lento = más viscoso
#define LAVA_NOISE_SCALE 2.5       // [1.5 2.0 2.5 3.5] escala del patrón
#define LAVA_EMISSION_STRENGTH 8.0 // [3.0 4.5 6.0 8.0 12.0] intensidad emisiva HDR (sube = brilla más)

// ---------- Constantes matemáticas ----------
const float PI  = 3.14159265359;
const float TAU = 6.28318530718;

// IDs de bloque (coinciden con block.properties). Literales float (.0).
#define ID_WATER   10000.0
#define ID_LAVA    10001.0
#define ID_ICE     10002.0   // hielo (se distingue del agua: usa su textura)
#define ID_PORTAL  10003.0   // portal del Nether (brillo lila emisivo)
#define ID_LEAVES  10020.0   // hojas (ondean como bloque entero)
#define ID_FOLIAGE 10021.0   // hierba/flores/cultivos (ondean desde la base)

// Colores de luz.
const vec3 SUN_COLOR  = vec3(1.00, 0.92, 0.78);
const vec3 MOON_COLOR = vec3(0.42, 0.52, 0.85);
const vec3 SKY_COLOR  = vec3(0.45, 0.62, 0.95);

#endif
