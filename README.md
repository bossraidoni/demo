# Visual Control Reborn

**Version 4.0.0**  
A self-contained, client-side Roblox visual environment suite for executor-injected Luau.

> Visual Control Reborn is a ground-up rebuild of Visual Control v3. It keeps the original purpose — beautiful local visuals and atmosphere — but replaces the interface, architecture, weather, environment sensing, audio processing, presets, persistence, and cleanup systems.

---

## Files

| File | Purpose |
| --- | --- |
| `VisualControlReborn.lua` | Complete source and ready-to-run distribution artifact. |
| `README.md` | Feature documentation, user guide, architecture, limitations. |
| `VALIDATION.md` | Static verification report and manual test checklist. |
| `CHANGELOG.md` | Major differences from Visual Control v3. |

There is no build step, external package, ModuleScript, remote code loading, or dependency. Execute `VisualControlReborn.lua` directly in the same client-side executor environment used by the original script.

---

## Quick start

1. Execute `VisualControlReborn.lua` as a client-side script.
2. Press **`=`** to show or hide the application.
3. Press **`Ctrl+K`** while the app is visible to open global settings search.
4. Use the left sidebar to switch between Dashboard, Graphics, Lighting, Atmosphere, Weather, Camera, Audio, Presets, Performance, and Settings.
5. To fully unload and restore everything, open **Settings → Application lifecycle → Unload & restore**.

Default behaviors:

- The interface opens on the Dashboard.
- The Natural preset is applied on a first run.
- Visual effects, atmosphere, clouds, environment sensing, and the custom audio engine start enabled.
- Weather starts as **Clear**.
- Custom music is not loaded until you provide a source.
- The quick dock appears at the bottom-right while the full window is hidden.

---

## Core guarantees

- Client-side only.
- No movement, hitbox, combat, health, replication, or network changes.
- No modification of game-owned sounds, `SoundGroup`s, or global `SoundService` effects.
- Every environment property Visual Control edits is snapshotted and restored on disable, bypass, or unload.
- Existing game-owned `Atmosphere` and `Clouds` objects are reused and restored; they are never destroyed.
- Own effects are named with the `VisualControlReborn_` prefix.
- Environmental raycasts are throttled and quality-controlled.
- All rendering features are real, supported Roblox APIs. No fake GPU shader claims.

---

## Interface tour

### Window behavior

- Drag by the empty area in the title bar.
- Minimize with the title-bar minimize control; restore from the same control.
- Hide with the title-bar **X** or the keybind.
- The quick dock appears while hidden, if enabled.
- The window automatically scales and stays within the viewport.
- The sidebar auto-collapses on narrow windows; manual collapse is also supported.
- `Esc` closes the active modal or dropdown.

### Header

- **Search** opens the global settings search palette.
- **Compare** is a hold control: hold it to bypass every Visual Control visual enhancement and show the original environment snapshot; release to restore.
- **Minimize** and **Hide** controls.
- The header remains visible when minimized.

### Dashboard

- Hero summary with active preset, environment, weather, and quick actions.
- Live metrics: environment classification, shelter, room estimate, FPS, frame time, precipitation estimate.
- Quick actions: next preset, cycle weather, play/pause personal music, open Settings.
- Active systems overview: Graphics, Atmosphere & Clouds, Weather, Environment sensing, Personal audio.
- Pinned controls: settings you star from any page.
- Live clock badge.

### Graphics

- Master visual-engine toggle and hold-to-compare.
- Color and tone: contrast, image brightness, saturation, color tint.
- Bloom: intensity, sun rays, sun-ray intensity.
- Advanced bloom: spread and threshold in a collapsible group.
- Screen vignette toggle and strength.

### Lighting

- Time-of-day override and slider.
- Dawn / Noon / Golden / Midnight quick segments.
- Adaptive eye exposure and response speed.
- Exposure bias.
- Weather color grading and grading strength.
- Enhanced environment lighting.

### Atmosphere

- Atmospheric scattering toggle.
- Density, haze, glare, atmosphere color.
- Weather-responsive atmosphere.
- Dynamic clouds toggle, cover, density, color.
- Live object status: game-owned reused / owned created / unavailable.

### Weather

- Five condition cards: Clear, Overcast, Rain, Snow, Fog.
- Intensity, wind-driven precipitation, shelter detection.
- Optional low-intensity lightning and lightning strength.
- Live rain/snow emission, shelter, and camera coverage meters.
- Weather transitions are gradual; rain and snow rates ramp instead of popping.

### Camera

- Client-side field-of-view override.
- Cinematic depth of field: toggle, quick styles, focus distance, in-focus radius, far blur, near blur.
- Original camera FOV is restored on disable, camera replacement, or unload.

### Audio

- Personal music player only. Game audio is untouched.
- Roblox asset IDs and supported local files.
- Play/pause, stop, previous/next queue track, loop, volume.
- Seek bar, position, duration, loading status, errors.
- Session queue with play/remove/clear.
- Environment-responsive indoor muffling and reverb applied only to the Visual Control `Sound` instance.
- Acoustic status shows indoor/room estimates.

### Presets

- Eight curated built-in presets:
  - Natural
  - Cinematic
  - Vibrant
  - Golden Hour
  - Overcast
  - Rainy
  - Midnight
  - Dreamlike
- Preset cards include a preview thumbnail, description, details modal, and apply action.
- Save the current look as a custom preset.
- Rename or delete custom presets with confirmation.
- Built-in and custom preset names are unique case-insensitively.
- Presets coordinate time, weather, atmosphere, clouds, post-processing, vignette, FOV, and depth of field.

### Performance

- Quality profiles: Low, Balanced, High.
- Live FPS, frame time, environment scan rate, estimated particles, active system count.
- Diagnostics: active preset, environment, weather, shelter/room, persistence, local audio support, clipboard support, uptime.
- Copy diagnostics to the clipboard when the executor supports `setclipboard`.
- Quality controls raycast frequency and precipitation density, not gameplay.

### Settings

- Accent palette.
- Reduced motion.
- Tooltips.
- Quick dock.
- Show/hide keybind rebinding.
- Optional local persistence.
- Save now / clear saved data.
- Hide window.
- Unload and restore.
- About / capability summary.

---

## Graphics system

Visual Control Reborn creates and owns its own post-processing instances:

- `BloomEffect`
- `ColorCorrectionEffect`
- `SunRaysEffect`
- `DepthOfFieldEffect`

Existing game-owned post-processing effects are never modified or removed. Visual Control's effects stack with the game's own effects, which is why the app exposes a master bypass and hold-to-compare.

Adaptive effects:

- **Dynamic eye adaptation** is a heuristic based on time of day, weather, shelter, and enclosure. It does not read framebuffer luminance.
- **Dynamic color grading** responds to time, rain, snow, fog, and overcast conditions.
- **Weather-responsive lighting** adjusts atmosphere, fog, exposure, clouds, and grading.
- **Environment-aware ambience** uses raycast-derived enclosure values.
- **Cinematic depth of field** is opt-in and visual only.
- **Vignette** is a non-interactive screen-edge overlay, not a game effect.

The implementation deliberately avoids claims of GPU shader injection, true ray tracing, HDR framebuffer access, or engine-level color grading that ordinary Luau cannot access.

---

## Weather system

### Rain

The new rain system is designed around visibility and reliability:

- Camera-following, world-aligned emitter volume (`170 × 2 × 170` studs).
- Built-in `rbxasset://textures/particles/rain_main.dds` streak texture.
- High emission rate with density controlled by the quality profile and weather intensity.
- Visible particle size, fade curve, additive light emission, and low-light visibility.
- Downward speed plus local wind acceleration.
- Multiple quality tiers.
- Gradual shelter reduction using both character and camera overhead coverage.
- Smooth clear/rain transitions.

The old v3 concern — rain not being visible — was treated as a first-class design issue: the new emitter uses a large volume around the camera, a substantially higher rate, a visible streak size, and a brightness/transparency configuration intended to remain readable in bright and dark scenes.

### Snow

- Slower fall speeds, varied lifetimes, gentle rotation, wind drift.
- Camera-facing snowflake billboards.
- Density, transition, and shelter response.
- Quality-scaled particle counts.

### Fog

- Roblox `FogStart`, `FogEnd`, and `FogColor` are adjusted alongside `Atmosphere`.
- Original fog values are snapshotted and restored.
- Fog, rain, snow, and overcast conditions blend into the atmosphere and color grade.

### Clouds

- Existing game-owned `Clouds` reused and restored.
- If none exists, a clearly named owned `Clouds` object is created under `Terrain`.
- Cover, density, color, and storm response.
- No global wind property modification.

### Lightning

- Optional and disabled by default.
- Rare, low-intensity overlay flashes.
- Suppressed by Reduced Motion.
- Visual only; no combat, sound, or gameplay interaction.

---

## Environment detection

The environment detector performs bounded client-side raycasts from the character and camera:

- 5 overhead rays around the character.
- 8 horizontal rays for wall enclosure.
- 3–5 camera overhead rays depending on quality.
- Approximate room size from wall hit distances.
- Continuous smoothed values for roof, wall, camera cover, room size, shelter, and indoor amount.
- Classification hysteresis to prevent rapid state flicker.
- Scan interval controlled by quality profile (approximately 3–10 scans per second, never per frame).
- Excludes the local character and Visual Control's own weather emitter.
- Uses `RespectCanCollide = true`, so non-collidable decorative geometry may not count as cover.

Classifications are approximate:

- Open air
- Sheltered
- Partially covered
- Indoor room
- Deep interior
- Tunnel / cave

These values feed weather sheltering, adaptive exposure, audio filtering, reverb, and the dashboard.

---

## Personal audio engine

### Isolation

The audio engine creates exactly one own `Sound` under an own `Folder` in `SoundService`:

- `VisualControlReborn_AudioFolder`
- `VisualControlReborn_Audio`
- `VisualControlReborn_IndoorEQ`
- `VisualControlReborn_IndoorReverb`

The equalizer and reverb are children of the Visual Control Sound instance. No game-owned Sound, SoundGroup, global effect, or `SoundService` property is modified.

### Sources

- Roblox audio asset IDs: `rbxassetid://1234567890` or a raw numeric ID.
- Local files through the executor's existing `getcustomasset` function when available.
- If `getcustomasset` is unavailable, local playback is rejected with a clear message while asset IDs continue to work.

### Playback

- Play, pause, resume, stop.
- Previous/next queue track.
- Loop.
- Volume.
- Seek via the progress bar.
- Duration and current position from Roblox's `Sound.TimeLength` / `TimePosition`.
- Loading and timeout handling.
- Track title from the local file name or asset ID. No metadata is fabricated.
- Session-only queue. Queue entries are not persisted.

### Indoor acoustics

- High/mid/low equalizer attenuation scales with enclosure and muffle strength.
- Reverb wet level and decay scale with enclosure and room size.
- Small roofs produce gentle filtering; enclosed spaces produce stronger filtering and more reverb.
- All transitions are smoothed.

---

## Presets and persistence

### Presets

Presets store the complete visual look:

- Post-processing, bloom, tint, sun rays, vignette
- FOV and depth of field
- Time override and clock time
- Adaptive exposure and color grading
- Atmosphere and clouds
- Weather and intensity
- Wind, shelter, and lightning

Audio, UI appearance, quality, and keybind are intentionally not part of visual presets.

Custom presets are captured from the current state, stored in memory, and optionally persisted.

### Optional local persistence

Persistence is enabled only when all of the following are available:

- `writefile`
- `readfile`
- `isfile`

The file is written to:

```text
VisualControlReborn_v4.json
```

Saved data includes:

- Visual and interface settings
- Accent choice
- Keybind
- Active preset
- Custom presets
- Dashboard favorites

Not saved:

- Audio queue
- Current track
- Window position
- Temporary compare/minimize/visibility state

When persistence is unavailable:

- The Settings page says so.
- The Remember Preferences switch is disabled.
- The application remains fully usable as a session-only tool.

`Save now` can force a save. `Clear saved data` deletes the file when `delfile` is available.

---

## Performance model

- One RenderStep update loop.
- One throttled UI refresh loop (approximately 5 Hz).
- Raycasts at quality-controlled intervals, never per frame.
- Reused effect, emitter, audio, and environment objects.
- No repeated instance creation during normal operation.
- Atmospheric and cloud property writes are throttled.
- Particle density scales with the selected quality profile.
- UI updates are event-driven where possible.
- Owner-scoped connections and dynamic UI scopes clean up temporary controls.
- Reduced Motion shortens animations and suppresses automatic lightning.

Quality profiles:

| Profile | Environment scan | Rain density | Snow density |
| --- | --- | --- | --- |
| Low | ~3.1/s | 0.42× | 0.48× |
| Balanced | ~5.9/s | 1.00× | 1.00× |
| High | ~10/s | 1.35× | 1.28× |

---

## Cleanup and restoration

On unload, close, external GUI destruction, or re-execution, Visual Control:

1. Saves preferences if enabled.
2. Stops the personal audio player.
3. Restores Lighting properties, fog, clock time, atmosphere, clouds, and camera FOV.
4. Removes its own post-processing, weather emitter, overlays, audio folder, and GUI.
5. Disconnects its connections and unbinds its RenderStep.
6. Clears dynamic UI scopes, signal handlers, theme bindings, and control bindings.
7. Removes its controller global.

When Visual Control is re-executed:

- A previous Visual Control Reborn controller is cleaned up first.
- Legacy Visual Control v3 GUI/effects/audio/weather leftovers are removed.
- A fresh original-environment snapshot is taken after cleanup.
- The new application starts from the saved preferences if available.

---

## Validation summary

Static validation performed in this repository:

- Luau 0.746 compiler: **passed**.
- Luau 0.746 analyzer: no cross-block unknown globals, no local-shadow hazards; remaining diagnostics are expected Roblox/executor globals and unused references.
- Roblox API dump checks: all 22 literal `Instance.new` class names valid and creatable; all 43 static enum references valid.
- Manual review of lifecycle, ownership, restoration, dynamic UI cleanup, audio isolation, and responsive layout.

**Not performed:** actual Roblox client runtime testing, including visual confirmation of rain/snow particles. No Roblox runtime was available or authorized for this build. See `VALIDATION.md` for details and a manual test checklist.

---

## Known limitations

1. **Client-side only.** Some games may overwrite local Lighting, Atmosphere, Clouds, fog, or camera FOV.
2. **No GPU shaders or true ray tracing.** Visuals are built from Roblox-supported post-processing, lighting, atmosphere, clouds, fog, particles, and UI.
3. **Adaptive exposure is heuristic.** It does not measure framebuffer luminance.
4. **Environment detection is approximate.** Non-collidable decorative geometry may not count as cover, and room classification is geometric guesswork.
5. **Weather particles do not collide with geometry.** Shelter is approximated through raycasts and emitter-rate reduction, not per-particle collision.
6. **Rain visibility was designed for reliability but not empirically tested in a Roblox client in this workspace.** The configuration uses a large camera-following volume, high rate, built-in streak texture, visible size, and brightness.
7. **Audio metadata is not exposed by Roblox.** Titles come from file names or asset IDs.
8. **Local audio depends on the executor.** Without `getcustomasset`, only Roblox asset IDs are supported.
9. **Persistence depends on executor filesystem APIs.** Without them, settings and custom presets are session-only.
10. **Queue and current track are session-only.**
11. **Lightning is optional and intentionally low intensity.** It is not a full storm simulation.
12. **FOV and DOF are visual features.** Some users may consider FOV gameplay-adjacent; both are opt-in.
13. **Quick dock can be disabled.** In that case, the configured keybind is the only way to reopen a hidden window.
14. **Mobile devices have no keyboard keybind.** The quick dock is the intended reopen path; keep it enabled on touch devices.
15. **Legacy v3 restoration can be incomplete if a previous v3 session lost its own snapshot.** Visual Control Reborn cleans legacy objects and takes a fresh snapshot, but cannot reconstruct values a prior script never recorded.
16. **Extremely small viewports** may compress labels and modal content. Normal desktop and tablet resolutions are the primary target.
17. **No GPU profiling data.** FPS and frame time are measured by this script, not by engine-level render statistics.
18. **Custom preset files validate types but not aesthetic ranges.** Hand-edited out-of-range values are clamped by controls where possible.

---

## Manual runtime test checklist

Use this checklist when a Roblox client is available:

1. Execute the script; confirm the splash and Dashboard appear.
2. Press `=` twice; confirm hide/show and quick dock.
3. Drag and minimize/restore the window; confirm boundary clamping.
4. Collapse and expand the sidebar; resize the viewport.
5. Open Settings search with `Ctrl+K`; search “bloom”, “rain”, and “Cinematic”.
6. Hold the header compare control; confirm the original look returns while held.
7. Apply every built-in preset; confirm smooth transitions and no errors.
8. Select Rain outdoors; confirm clearly visible streaks in bright and dark scenes.
9. Move under a solid roof; confirm rain fades gradually.
10. Select Snow; confirm visible drifting flakes.
11. Select Fog; confirm fog and atmosphere transitions.
12. Enable lightning; confirm occasional low-intensity flashes and no combat interference.
13. Enter a Roblox audio asset ID; confirm play/pause/stop/seek/loop.
14. Enter a local audio path; confirm `getcustomasset` behavior.
15. Walk indoors; confirm only the custom track is muffled/reverbed.
16. Verify a game-owned sound is unaffected.
17. Reload or re-execute; confirm no duplicate GUI, effects, audio, or weather parts.
18. Unload and confirm Lighting, fog, time, Atmosphere, Clouds, and camera FOV restore.
19. With filesystem APIs available, save preferences and re-execute; confirm restoration.
20. With filesystem APIs unavailable, confirm session-only behavior and clear messaging.

---

## Architecture overview

`VisualControlReborn.lua` is a single distribution artifact organized into internal modules:

- Services and executor compatibility
- Utilities, signals, motion, theme
- Settings defaults and curated presets
- Optional local persistence
- Original environment snapshots and legacy cleanup
- Quality profiles and metrics
- Environment detector
- Screen overlay / vignette / lightning
- Weather engine
- Graphics engine
- Lighting manager
- Atmosphere and cloud manager
- Personal audio engine
- Camera manager
- Control registry
- UI framework and reusable components
- Application shell and window behavior
- Pages and navigation
- Search, quick dock, settings synchronization
- Update loop, initialization, cleanup

The code deliberately keeps effect ownership explicit: every created object either has a known prefix or is a snapshot-restored game object.

---

## Changelog summary

See `CHANGELOG.md` for the full list. Highlights:

- Entire interface rebuilt with ten pages, sidebar navigation, animated tabs, modals, dropdowns, sliders, switches, search, toasts, quick dock, and favorites.
- New modular graphics, lighting, atmosphere, weather, environment, camera, and audio engines.
- New visible rain/snow design and shelter-aware precipitation.
- New environment detector with hysteresis and quality-scaled raycasts.
- New isolated personal audio player with seek, queue, loading states, indoor EQ, and reverb.
- Eight curated presets plus custom preset management and optional persistence.
- Owner-scoped UI cleanup, restoration snapshots, and re-execution handling.
- Performance profiles, diagnostics, reduced motion, and responsive layout.
