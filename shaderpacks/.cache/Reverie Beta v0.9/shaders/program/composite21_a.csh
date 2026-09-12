// https://bruop.github.io/exposure/
// Stage 1: Calculate the histogram

#include "/lib/all_the_libs.glsl"

const float MINIMUM_LUMINANCE = -5.0;
const float MAXIMUM_LUMINANCE = 3.0;
const float LUM_RANGE_INV = 1.0 / (MAXIMUM_LUMINANCE - MINIMUM_LUMINANCE);

const float RESOLUTION_SCALE = 1;

// Shared histogram buffer used for storing intermediate sums for each work group
shared uint histogramShared[256];

// For a given color and luminance range, return the histogram bin index
uint colorToBin(vec3 hdrColor) {
  // Convert our RGB value to Luminance, see note for RGB_TO_LUM macro above
  float lum = get_luminance(hdrColor);

  // Avoid taking the log of zero
  if (lum < 0.01) {
    return 0;
  }

  // Calculate the log_2 luminance and express it as a value in [0.0, 1.0]
  // where 0.0 represents the minimum luminance, and 1.0 represents the max.
  float logLum = clamp((log2(lum) - MINIMUM_LUMINANCE) * LUM_RANGE_INV, 0.0, 1.0);

  // Map [0, 1] to [1, 255]. The zeroth bin is handled by the epsilon check above.
  return uint(logLum * 254.0 + 1.0);
}

const vec2 workGroupsRender = vec2(1, 1);

layout(local_size_x = 16, local_size_y = 16) in;
void main() {
  // Initialize the bin for this thread to 0
  histogramShared[gl_LocalInvocationIndex] = 0;
  barrier();
  // Ignore threads that map to areas beyond the bounds of our HDR image
  vec2 Pos = gl_GlobalInvocationID.xy / RESOLUTION_SCALE;
  if (all(lessThan(Pos, resolution))) {
    vec3 hdrColor = texelFetch(colortex0, ivec2(Pos), 0).rgb;
    uint binIndex = colorToBin(hdrColor);
    // We use an atomic add to ensure we don't write to the same bin in our
    // histogram from two different threads at the same time.
    atomicAdd(histogramShared[binIndex], 1);
  }

  // Wait for all threads in the work group to reach this point before adding our
  // local histogram to the global one
  barrier();

  // Technically there's no chance that two threads write to the same bin here,
  // but different work groups might! So we still need the atomic add.
  atomicAdd(histogramBuf.data[gl_LocalInvocationIndex], histogramShared[gl_LocalInvocationIndex]);
}