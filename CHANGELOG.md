# Changelog

## Visual Control Reborn 4.0.0

This is a ground-up rebuild, not an incremental v3 patch.

### Interface

- Replaced the single scrolling panel with a ten-page application:
  - Dashboard
  - Graphics
  - Lighting
  - Atmosphere
  - Weather
  - Camera
  - Audio
  - Presets
  - Performance
  - Settings
- Added a collapsible sidebar, animated page transitions, live status badges, responsive scaling, and viewport boundary clamping.
- Added a centralized animation system with consistent easing, durations, reduced-motion support, and cleanup-safe motion.
- Added reusable components:
  - Animated switches
  - Drag sliders with numeric input
  - Segmented controls
  - Custom dropdowns
  - Color picker
  - Searchable settings palette
  - Tooltips
  - Preset cards
  - Toasts
  - Confirmation dialogs
  - Collapsible groups
  - Status indicators
- Added a quick dock for preset, weather, audio, and reopen controls while the main window is hidden.
- Added hold-to-compare behavior for the original environment snapshot.
- Added dashboard favorites/pinned controls.
- Added accent color customization.
- Added reduced motion, tooltips, quick dock, keybind rebinding, and persistence controls.
- Added a boot splash and polished initialization sequence.
- Added responsive grid layouts for metrics, weather cards, preset cards, and color swatches.

### Graphics

- Replaced the fixed v3 effect stack with a modular owned graphics engine.
- Added independent controls for:
  - Bloom intensity, spread, threshold
  - Contrast, image brightness, saturation
  - Color tint with a color picker
  - Sun rays and intensity
  - Vignette
  - Depth of field
  - FOV
- Added time- and weather-responsive color grading.
- Added heuristic adaptive exposure with response speed and exposure bias.
- Added enhanced environment diffuse/specular lighting and ambient tinting.
- Added a proper original-property snapshot and restoration path.
- Added a non-interactive vignette overlay using supported GUI gradients.
- Added compare bypass without changing the user's saved settings.

### Atmosphere and lighting

- Added a dedicated atmosphere manager that reuses game-owned `Atmosphere` and restores it.
- Added owned fallback `Atmosphere` creation when none exists.
- Added density, haze, glare, color, and weather-response controls.
- Added cloud cover, density, and color controls.
- Added game-owned `Clouds` reuse and restoration.
- Added owned fallback `Clouds` creation.
- Added weather-responsive cloud/storm transitions.
- Added time-of-day override with a 24-hour slider and quick segments.
- Added live object status reporting.
- Added weather-driven fog control with original restoration.

### Weather

- Completely replaced the v3 weather implementation.
- Added a camera-following world-aligned particle volume.
- Redesigned rain for visibility:
  - Larger emitter volume
  - Much higher emission rate
  - Visible streak size
  - Built-in rain texture
  - Light emission and low-light visibility
  - Quality-scaled density
- Added snow with slower fall, rotation, drift, and quality-scaled density.
- Added Overcast as a weather condition.
- Added wind-driven precipitation.
- Added gradual shelter-aware precipitation using character and camera overhead coverage.
- Added smooth weather intensity transitions.
- Added optional low-intensity lightning with reduced-motion suppression.
- Added live rain/snow/shelter/camera diagnostics.
- Added fog, rain, snow, overcast, cloud, and color-grade coordination.

### Environment detection

- Added a centralized environment detector.
- Added overhead, wall, and camera raycasts.
- Added roof, wall, camera cover, room size, shelter, and indoor values.
- Added classification hysteresis to prevent flicker.
- Added quality-scaled scan intervals.
- Added character respawn and camera replacement resilience.
- Connected environment values to weather sheltering, eye adaptation, audio muffling, reverb, and dashboard status.

### Camera

- Added client-side FOV override with original per-camera restoration.
- Added cinematic depth of field with focus distance, radius, near blur, and far blur.
- Added quick DOF styles.
- Added camera replacement handling.
- Kept camera changes visual-only.

### Personal audio

- Replaced the v3 audio player with a full personal music engine.
- Added play, pause, resume, stop, seek, duration, position, loading status, and errors.
- Added a session playback queue with play, remove, clear, previous, and next.
- Added track titles derived from file names or asset IDs only.
- Added local file support through optional `getcustomasset`.
- Added Roblox asset ID support.
- Added equalizer and reverb exclusively on the Visual Control Sound instance.
- Added smooth enclosure-aware muffling and reverb.
- Added acoustic status diagnostics.
- Preserved the mandatory isolation guarantee: no game audio or global SoundService effects are touched.
- Added clear messaging when executor APIs are unavailable.

### Presets

- Replaced simple value presets with eight curated visual experiences:
  - Natural
  - Cinematic
  - Vibrant
  - Golden Hour
  - Overcast
  - Rainy
  - Midnight
  - Dreamlike
- Added coordinated time, weather, atmosphere, clouds, post-processing, vignette, FOV, and DOF.
- Added preset cards, thumbnails, details modals, and apply actions.
- Added custom preset creation, rename, delete, and case-insensitive validation.
- Added active preset indication and a Custom state after manual changes.
- Added optional persistence for custom presets.

### Performance and diagnostics

- Added Low, Balanced, and High quality profiles.
- Added quality-scaled raycasts and precipitation.
- Added live FPS, frame time, scan rate, particle estimate, and active system count.
- Added a diagnostics panel and clipboard export.
- Added a single throttled UI refresh and one RenderStep engine loop.
- Added owner-scoped cleanup and no repeated effect/emitter creation.

### Robustness and cleanup

- Added re-execution cleanup for the previous Visual Control Reborn controller.
- Added legacy v3 cleanup for known GUI, effect, weather, and audio objects.
- Added cleanup-before-snapshot ordering.
- Added original Lighting, fog, atmosphere, clouds, camera FOV, and time restoration.
- Added external GUI destruction handling.
- Added dynamic UI scopes for search, pinned controls, audio queue, dropdowns, modals, and toasts.
- Added owner-bound theme and signal cleanup.
- Added save-before-unload behavior.
- Added optional local persistence with validation and clear errors.
- Added responsive scaling and safe boundaries.
- Added reduced motion and photosensitivity-conscious lightning defaults.

### Validation

- Added a complete static validation pass with Luau 0.746.
- Added Roblox API class and enum reference validation.
- Documented that Roblox client runtime testing was not available.
- Added a manual runtime test checklist for rain visibility, shelter, audio isolation, restoration, and re-execution.
