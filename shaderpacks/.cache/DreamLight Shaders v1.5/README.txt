DreamLight Shaders v1.5
by HoneyStudios

A warm, dreamy visual experience for Minecraft.

DreamLight Shaders focuses on soft tones, balanced lighting, and smooth performance
- perfect for cozy, atmospheric worlds. It enhances sunlight, skies, and reflections
while keeping the look natural and soothing.


v1.5 Changes
------------

New:
- Water Foam is now actually implemented. In v1.4 the toggle existed in the
  settings menu but no code was ever wired up, so turning it on did nothing.
  It now renders animated foam where water meets terrain, with new
  "Foam Strength" and "Foam Width" sliders.
- Water Caustics is now actually implemented, for the same reason. Rippling
  light patterns appear on the ground under shallow water, with a new
  "Caustics Strength" slider.
- Depth of Field and Image Sharpening can now be enabled at the same time.
  Previously enabling DoF silently disabled sharpening. In-focus areas are
  sharpened; out-of-focus areas are blurred.

Fixed:
- Settings menu labels were wrong. A duplicated block of translation strings
  had been appended to en_US.lang in v1.4, and because later entries win, the
  TAA mode names were showing swapped - "Fancy" where the shader actually runs
  Denoise Only, and vice versa. The duplicate block is gone and the labels now
  match what the code does.
- The "Ethereal" colour scheme and the "DreamLight" tonemap operator now show
  their proper names instead of falling back to raw setting IDs.
- Removed a leftover noise sample in the cloud silver-lining code. The result
  was computed every frame for every sky pixel and then discarded - six wasted
  texture fetches per pixel of sky.
- Fixed a possible divide-by-zero in the luminance-preserving colour mix, which
  could produce black or NaN speckles in very dark water and fog.
- Contrast can no longer push colour channels negative before tonemapping.
- DoF Strength above roughly 0.8 previously had no effect because the blur
  radius was clamped too tightly. The clamp has been raised so the whole
  slider range is usable.
- Minor cleanups: removed dead code in the underwater tint, cached repeated
  random() lookups in the star field, and made the atmospheric fog height
  falloff branchless.

Translations:
- French and Simplified Chinese were missing every option added in v1.4
  (Depth of Field, Cloud Silver Lining, Water Foam, Water Caustics and the
  Ethereal scheme). Those strings have been added, along with the new v1.5
  sliders.

Notes:
- Water Foam and Water Caustics are not applied to Distant Horizons water,
  where the depth information they rely on is not available.
- Presets: Fast disables both. Fancy enables caustics. Fabulous enables both.


Credits
-------

DreamLight Shaders is a remake of Mellow Shader by TheCMK, used under the MIT
License. Original Mellow Shader:
https://www.curseforge.com/minecraft/shaders/mellow

Special thanks to TheCMK for the original creative base and inspiration.

See LICENSE.txt for the full license text and third-party notices.
