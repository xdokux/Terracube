# HyperShader

Shader pack base hiperrealista para **Minecraft (Fabric + Iris + Sodium)**,
optimizado para iGPU portátiles (objetivo: AMD Radeon 610M, 6–8 chunks).

## Novedades v1.1 — "Clima Vivo"

**Clima** (pestaña nueva en el menú):
- El mundo se **moja al llover**: bloques más oscuros y saturados, con brillo especular.
- **Charcos** en el suelo a cielo abierto (con reflejo del cielo y chispas de gotas).
- **Gotas de lluvia** ondulando la superficie del agua.
- **Sombras de nubes** moviéndose por el terreno (la misma nube que ves arriba).
- Cielo y niebla **encapotados** durante la tormenta; nubes grises; menos sol directo.
- **Arcoíris** al escampar (aparece solo tras la lluvia y se desvanece).
- **Relámpagos** que iluminan cielo y terreno (uniform de Iris).

**Agua 2.0**:
- **Cáusticas**: filamentos de luz bailando en el fondo (desde fuera y buceando).
- **Refracción**: el fondo se deforma a través de las olas.
- **Espuma** en las orillas.
- **SSR mejorado**: refinamiento binario (adiós "rayas"), fade en los bordes de
  pantalla y paso creciente (más alcance con el mismo coste).

**Confort**:
- **FXAA** (antialiasing casi gratis) en el pase final.
- **Perfiles** en el menú: `FAST` / `BALANCED` / `FANCY`.
- **Luz dinámica en mano**: la antorcha ilumina al caminar (Overworld, Nether y End).
- **Titileo de estrellas** por la noche.

## Instalación
1. Instala **Fabric** + **Sodium** + **Iris** para tu versión de Minecraft.
2. Copia la carpeta `HyperShader` completa en:
   `.minecraft/shaderpacks/`
3. En el juego: *Options → Video Settings → Shader Packs* → selecciona **HyperShader**.
4. (Opcional pero recomendado) Activa un resource pack **LabPBR** para que
   funcionen el normal mapping y el POM (mapas en el canal de `normals`).

## Los 4 pilares y dónde vive cada uno
| Pilar | Archivos clave |
|-------|----------------|
| 1. Agua (Gerstner + SSR + profundidad) | `lib/gerstner.glsl`, `gbuffers_water.*`, `composite.fsh` |
| 2. Lava fluida e incandescente | `lib/lava.glsl`, `gbuffers_terrain.*` |
| 3. Sombras suaves (PCSS) + God Rays | `lib/shadows.glsl`, `shadow.*`, `gbuffers_terrain.fsh`, `composite.fsh` |
| 4. PBR (normal map + POM) | `lib/parallax.glsl`, `gbuffers_terrain.*` |

## Pipeline (orden de ejecución)
`shadow` → `gbuffers_*` (terrain/water) → `composite` (SSR, god rays) → `final` (tone mapping).

## Notas de rendimiento (610M)
- Empieza con: `SSR_STEPS=12`, `GODRAY_SAMPLES=6`, `SHADOW_SAMPLES=4`,
  `POM_LAYERS=16`, `shadowMapResolution=1536`.
- Si va justo: baja primero `SSR_STEPS`, luego `POM_LAYERS`, luego la
  resolución de sombras. El SSR y el POM son los que más cuestan.
- Distancia de render: 6–8 chunks (menú normal de Minecraft).

## Caveats (es una BASE para iterar)
- El SSR es un raymarch lineal sencillo: puede dejar "rayas" en bordes;
  añade refinamiento binario y fade en los bordes de pantalla si lo notas.
- Los God Rays son screen-space (radiales). Para volumetría física real,
  raymarchea el shadow map en `composite` (más caro).
- El POM asume heightmap en `normals.a` (LabPBR). Si el relieve sale
  invertido, quita el `1.0 -` en `lib/parallax.glsl`.
- Sin resource pack PBR, el normal mapping/POM no tendrán datos (se ve plano,
  pero no rompe nada).
