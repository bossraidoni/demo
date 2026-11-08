# Validation Report

## Scope

This report separates:

1. Static verification performed in the workspace.
2. Manual code-review verification.
3. Roblox runtime testing status.

The implementation was **not** executed in a live Roblox client in this workspace. No claim of runtime success, visual confirmation of rain/snow, or real-device UI validation is made.

---

## 1. Static verification

### Toolchain

- Luau compiler/analyzer: `luau` 0.746 Windows release.
- Compiler command:

```powershell
luau-compile.exe --binary VisualControlReborn.lua > $null
```

- Result: **exit code 0, compile OK**.

### Analyzer

Command:

```powershell
luau-analyze.exe VisualControlReborn.lua
```

Summary of diagnostics:

| Category | Count | Interpretation |
| --- | ---: | --- |
| `UnknownGlobal` | 1259 | Expected: Roblox globals (`game`, `Enum`, `Instance`, `UDim2`, etc.) and guarded executor globals (`getcustomasset`, `writefile`, etc.) are not in the standalone analyzer environment. |
| `LocalUnused` | 75 | Intentionally retained creation references and benign unused local returns. |
| `UnknownType` | 7 | Roblox datatypes (`Color3`) not defined in the standalone analyzer. |
| `FunctionUnused` | 4 | Utility helpers retained for clarity. |
| `ImplicitReturn` | 2 | Analyzer style warning in guarded executor-function capture blocks. |

A filtered check for non-Roblox/non-executor unknown globals and `LocalShadow` warnings returned **zero results**. In particular, no cross-IIFE/local-scope references were left unresolved.

### Roblox API surface checks

Using the current Roblox API dump:

- Literal `Instance.new(...)` classes: **22**
- Invalid or non-creatable literal classes: **0**
- Static `Enum.EnumName.Item` references: **43**
- Invalid static enum items: **0**

Additional checks:

- `ClearAllChildren`: **0 occurrences** (dynamic lists preserve their layout modifiers and destroy only GUI children).
- `TODO` / `FIXME`: **0 occurrences**.
- UTF-8 replacement characters: **0**.
- Unicode UI glyphs remain valid UTF-8.

Note: classes created through the `createOwnedEffect` helper (`BloomEffect`, `ColorCorrectionEffect`, `SunRaysEffect`, `DepthOfFieldEffect`) were reviewed manually against the API dump and are valid.

### Source statistics

- Lines: approximately 10,500.
- Size: approximately 356 KB.
- Single self-contained distribution file.
- No external ModuleScripts, packages, remotes, or remote code loading.

---

## 2. Manual code-review verification

The following areas were reviewed manually:

### Lifecycle and ownership

- Previous Visual Control Reborn controller cleanup via a guarded global controller table.
- Legacy v3 GUI, effect, weather, and audio cleanup.
- Cleanup-before-snapshot ordering.
- Original Lighting, fog, clock, Atmosphere, Clouds, and camera FOV snapshots.
- Owned effect/object prefixes.
- Game-owned Atmosphere/Clouds reuse and restoration.
- External GUI destruction handling.
- Re-execution behavior.
- Idempotent cleanup guard.
- Save-before-unload behavior.

### Environment and weather

- Raycast counts and intervals bounded by quality.
- Character/camera exclusion filter.
- Classification hysteresis.
- Shelter reduction uses both character and camera overhead coverage.
- Camera-following weather volume.
- Rain emitter uses a large volume, high rate, visible size, built-in streak texture, and light emission.
- Snow uses slower fall, rotation, drift, and quality scaling.
- Fog and atmosphere restoration.
- Cloud reuse/restore.
- Lightning reduced-motion suppression and low intensity.

### Audio isolation

- Exactly one owned Sound under one owned Folder.
- Equalizer and reverb parented to that Sound.
- No global `SoundService` effect or `SoundGroup` writes.
- Local file support guarded by optional `getcustomasset`.
- Asset ID support independent of executor APIs.
- Queue and playback state isolated to the owned Sound.
- Loading timeout and already-loaded playback handling.

### UI and cleanup

- Dynamic lists preserve `UIListLayout`/`UIGridLayout` when rebuilding.
- Search, queue, pinned controls, custom presets, dropdowns, modals, and toasts use scopes or owner-bound connections.
- Theme bindings are owner-bound where dynamic.
- Control bindings are cleared at cleanup.
- Delayed tasks check for closed/destroyed state where they touch UI.
- Responsive grid sizing accounts for child-count changes as well as width changes.
- Page/transition cleanup generation guards.
- Modal close and navigation guards.
- Reduced-motion path.
- Layout ordering normalized for deterministic stacking.
- Window boundary and viewport scaling review.
- Quick dock and minimized/hidden window review.

### Known static limitations

- The standalone analyzer does not understand Roblox Instances or properties.
- Layout, rendering, particle visibility, asset loading, and executor APIs cannot be validated statically.
- Particle visibility remains a runtime property of the actual Roblox client and graphics settings.

---

## 3. Roblox runtime testing status

**Not performed.**

Reasons:

- No Roblox Studio executable or authorized local Roblox test runtime was available in the workspace.
- A live Roblox client session was not authorized for this task.
- Therefore, no evidence exists for:
  - Actual rain/snow particle visibility.
  - Visual layout on specific screen sizes.
  - Actual executor `getcustomasset` behavior.
  - Actual executor filesystem persistence behavior.
  - Actual game-owned audio isolation in a specific game.
  - Actual restoration after a specific game modifies Lighting concurrently.

The implementation is designed for these cases, but runtime verification is still required before claiming production readiness in a specific game.

---

## 4. Required manual runtime checklist

Use the checklist in `README.md` under **Manual runtime test checklist**. The highest-priority tests are:

1. Rain visibility outdoors in day and night scenes.
2. Gradual rain reduction under a solid roof.
3. Snow visibility and density.
4. Only the Visual Control Sound is equalized/reverbed indoors.
5. Game-owned sounds are unchanged.
6. Original Lighting, fog, time, Atmosphere, Clouds, and FOV restore on unload.
7. Re-execution leaves no duplicate GUI/effects/audio/weather part.
8. Dynamic queues, pinned controls, search results, and custom preset grids render correctly after rebuilds.
9. Quick dock and hidden-window behavior on desktop and touch.
10. Executor persistence and local audio support.

---

## 5. Honest assessment

- The source is syntactically valid Luau and passes static API reference checks for classes/enums.
- The architecture, ownership, cleanup, and UI component systems have been manually reviewed.
- The rain design directly addresses the v3 visibility problem through higher density, a larger camera-following volume, a visible built-in streak texture, and brightness/size tuning.
- This is still a supported-API approximation, not a GPU shader or ray-traced renderer.
- Runtime testing in Roblox remains necessary, particularly for particle visibility and game-specific property overwrites.
