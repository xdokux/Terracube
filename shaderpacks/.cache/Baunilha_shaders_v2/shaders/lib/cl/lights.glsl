#ifndef COLOUR_LIGHTS_GLSL
#define COLOUR_LIGHTS_GLSL

struct ColouredLight {
    uint blockID;
    float blockLightLevel;
    vec3 lightColour;
    bool natural;
};

const ColouredLight[] colouredLights = ColouredLight[47](
    ColouredLight(89, 15, vec3(1.0, 0.43, 0.0), true),     // [0] Glowstone (Confirmado)
ColouredLight(91, 15, vec3(1.0, 0.54, 0.0), true),     // [1] Jack o lantern
                                                         ColouredLight(138, 15, vec3(1.0, 1.0, 1.0), true),    // [2] Beacon
                                                         ColouredLight(169, 15, vec3(0.0, 0.5, 1.0), true),    // [3] Sea lantern
                                                         ColouredLight(213, 3, vec3(1.0, 0.3, 0.0), true),     // [4] Magma block

                                                         // Concretos Coloridos
                                                         ColouredLight(251, 10, vec3(1.0, 0.35, 0.0), false),   // [5] Orange concrete (Corrigido para ID base 251)
ColouredLight(253, 10, vec3(0.0, 0.3, 0.8), false),    // [6] Light blue concrete
                                                         ColouredLight(254, 10, vec3(1.0, 1.0, 0.0), false),    // [7] Yellow concrete
                                                         ColouredLight(255, 10, vec3(0.0, 0.8, 0.0), false),    // [8] Lime concrete
                                                         ColouredLight(260, 10, vec3(0.6, 0.0, 0.6), false),    // [9] Purple concrete
                                                         ColouredLight(264, 10, vec3(1.0, 0.0, 0.0), false),    // [10] Red concrete

                                                         // Iluminação Geral
                                                         ColouredLight(463, 15, vec3(1.0, 0.54, 0.0), true),    // [11] Lantern
                                                         ColouredLight(464, 15, vec3(1.0, 0.52, 0.0), true),    // [12] Campfire
                                                         ColouredLight(485, 15, vec3(1.0, 0.33, 0.0), true),    // [13] Shroomlight
                                                         ColouredLight(544, 10, vec3(0.5, 0.0, 1.0), true),    // [14] Crying obsidian

                                                         // Froglights (Corrigidos os IDs para sequência padrão)
                                                         ColouredLight(724, 15, vec3(0.9, 0.6, 0.9), true),    // [15] Pearlescent froglight
                                                         ColouredLight(725, 15, vec3(0.6, 0.9, 0.6), true),    // [16] Verdant froglight
                                                         ColouredLight(726, 15, vec3(0.9, 0.8, 0.5), true),    // [17] Ochre froglight

                                                         // Elementos das Almas (Soul) e Redstone
                                                         ColouredLight(465, 10, vec3(0.3, 0.7, 0.9), true),     // [18] Soul lantern
                                                         ColouredLight(466, 10, vec3(0.3, 0.7, 0.9), true),     // [19] Soul torch / Soul fire
                                                         ColouredLight(467, 7, vec3(1.0, 0.0, 0.0), true),      // [20] Redstone torch
                                                         ColouredLight(468, 13, vec3(0.91, 0.46, 0.11), true),   // [21] Furnace
                                                         ColouredLight(469, 14, vec3(0.9, 0.9, 1.0), true),     // [22] End rod
                                                         ColouredLight(470, 15, vec3(1.0, 0.4, 0.0), true),     // [23] Lava
                                                         ColouredLight(471, 15, vec3(1.0, 0.5, 0.0), true),     // [24] Fire
                                                         ColouredLight(472, 14, vec3(0.87, 0.75, 0.27), true),   // [25] Cave vines
                                                         ColouredLight(473, 15, vec3(0.3, 0.8, 0.8), true),     // [26] Conduit
                                                         ColouredLight(474, 13, vec3(0.6, 0.1, 0.8), true),     // [27] Respawn anchor
                                                         ColouredLight(475, 10, vec3(0.0, 0.4, 0.5), true),     // [28] Sculk catalyst
                                                         ColouredLight(480, 6, vec3(1.0, 0.0, 0.0), false),     // [29] Redstone block

                                                         // Blocos de Cobre (Copper Bulbs / Torches - Corrigidos para a faixa estável)
                                                         ColouredLight(491, 14, vec3(0.15, 0.93, 0.65), true),   // [30] Copper torch
                                                         ColouredLight(492, 15, vec3(0.12, 0.95, 0.60), true),   // [31] Copper lantern
                                                         ColouredLight(493, 15, vec3(0.96, 0.55, 0.25), true),   // [32] Copper bulb
                                                         ColouredLight(494, 12, vec3(0.87, 0.75, 0.27), true),   // [33] Firefly bush

                                                         // Categorias Globais (IDs altos mapeados por aproximação de tags)
                                                         ColouredLight(15008, 10, vec3(0.36, 0.78, 0.89), true), // Soul lantern (cat)
ColouredLight(15408, 10, vec3(0.36, 0.78, 0.89), true), // Soul fire (cat)
ColouredLight(15001, 7, vec3(0.88, 0.23, 0.23), true),  // Redstone torch (cat)
ColouredLight(15014, 13, vec3(0.91, 0.46, 0.11), true), // Furnace (cat)
ColouredLight(15003, 15, vec3(1.0, 0.43, 0.0), true),   // Glowstone (cat)
ColouredLight(15002, 15, vec3(1.0, 0.54, 0.0), true),   // Torch/Lantern/Campfire (cat)
ColouredLight(15007, 15, vec3(0.0, 0.0, 1.0), true),    // Sea lantern (cat)
ColouredLight(15005, 15, vec3(0.0, 1.0, 0.0), true),    // Verdant froglight (cat)
ColouredLight(15009, 15, vec3(1.0, 0.0, 1.0), true),    // Pearlescent froglight (cat)
ColouredLight(15025, 14, vec3(1.0, 1.0, 1.0), true),    // End rod/Beacon (cat)
ColouredLight(15302, 15, vec3(0.95, 0.47, 0.10), true), // Lava (cat)
ColouredLight(15402, 15, vec3(0.95, 0.47, 0.10), true), // Fire (cat)
ColouredLight(15709, 14, vec3(0.87, 0.75, 0.27), true)  // Cave vines (cat)
);

#endif
