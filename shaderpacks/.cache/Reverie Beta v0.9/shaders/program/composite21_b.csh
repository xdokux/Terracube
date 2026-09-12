// https://bruop.github.io/exposure/
// Stage 1: Calculate the average exposure

#include "/lib/all_the_libs.glsl"

const float MINIMUM_LUMINANCE = -5.0;
const float MAXIMUM_LUMINANCE = 3.0;
const float LUM_RANGE = (MAXIMUM_LUMINANCE - MINIMUM_LUMINANCE);

const float RESOLUTION_SCALE = 1;

shared uint histogramShared[256];

#define localIndex gl_LocalInvocationIndex

const ivec3 workGroups = ivec3(1, 1, 1);
layout(local_size_x = 256, local_size_y = 1) in;
void main() {
  // Get the count from the histogram buffer
  uint countForThisBin = histogramBuf.data[localIndex];
  histogramShared[localIndex] = countForThisBin * localIndex;

  barrier();

  // Reset the count stored in the buffer in anticipation of the next pass
  histogramBuf.data[localIndex] = 0;

  // This loop will perform a weighted count of the luminance range
  for (uint cutoff = (256 >> 1); cutoff > 0; cutoff >>= 1) {
    if (uint(localIndex) < cutoff) {
      histogramShared[localIndex] += histogramShared[localIndex + cutoff];
    }

    barrier();
  }

  // We only need to calculate this once, so only a single thread is needed.
  if (localIndex == 0) {
    // Here we take our weighted sum and divide it by the number of pixels
    // that had luminance greater than zero (since the index == 0, we can
    // use countForThisBin to find the number of black pixels)
    float weightedLogAverage = (histogramShared[0] / max(resolution.x * resolution.y * RESOLUTION_SCALE * RESOLUTION_SCALE, 1.0)) - 1.0;

    // Map from our histogram space to actual luminance
    float weightedExposure = exp2(((weightedLogAverage / 254) * LUM_RANGE) + MINIMUM_LUMINANCE);

    // The new stored value will be interpolated using the last frames value
    // to prevent sudden shifts in the exposure.
    float lumLastFrame = max(1e-6, dataBuf.AvgLum); // This max is needed for amd
    float adaptedLum = lumLastFrame + (weightedExposure - lumLastFrame) * frameTime * EXPOSURE_SPEED;
    
    dataBuf.AvgLum = max(1e-6, adaptedLum); // This max is needed for nvidia
  }
}