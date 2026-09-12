#ifndef CINDERLIGHT_MATERIALS_GLSL
#define CINDERLIGHT_MATERIALS_GLSL

const float MATERIAL_WATER = 10001.0;
const float MATERIAL_PLANT = 10010.0;
const float MATERIAL_TALL_PLANT = 10011.0;
const float MATERIAL_CROP = 10012.0;
const float MATERIAL_LEAVES = 10020.0;

bool isPlantMaterial(float materialId) {
    return abs(materialId - MATERIAL_PLANT) < 0.25 ||
           abs(materialId - MATERIAL_TALL_PLANT) < 0.25 ||
           abs(materialId - MATERIAL_CROP) < 0.25;
}

bool isLeafMaterial(float materialId) {
    return abs(materialId - MATERIAL_LEAVES) < 0.25;
}

bool isWaterMaterial(float materialId) {
    return abs(materialId - MATERIAL_WATER) < 0.25;
}

#endif
