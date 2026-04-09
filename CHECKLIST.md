# Implementation Checklist — Bistro Scene Viewer

Track progress here. Check off sub-phases as they are completed.
**Rule: Stop after completing each top-level phase and wait for user review before proceeding to the next phase.**

---

## Phase 0: Scaffolding
_No visual changes. Verify everything compiles._

- [x] **0.1** Create directory structure: `ThirdParty/ufbx/`, `ThirdParty/imgui/`, `ThirdParty/dds_loader/`, `Import/`, `Scene/`, `GPU/`
- [x] **0.2** Vendor `ufbx.h` + `ufbx.c`, add to Xcode targets, verify compilation
- [x] **0.3** Vendor Dear ImGui core + Metal + macOS backends, add to Xcode targets, verify compilation
- [x] **0.4** Write `ThirdParty/dds_loader/DDSLoader.h/mm` (DDS header parser → MTLTexture with BCn formats), test with one Bistro texture
- [x] **0.5** Write `Scene/RenderOptions.h` (C++ struct with all toggle fields)
- [x] **0.6** Build all macOS Xcode targets — no compile errors

**STOP — wait for user review before starting Phase 1.**

---

## Phase 1: Import Layer
_Goal: FBX → engine-independent C++ structs._

- [x] **1.1** Write `Import/ImportedScene.h` — plain C++ structs: `ImportedMesh`, `ImportedMaterial`, `ImportedNode`, `ImportedScene`
- [x] **1.2** Write `Import/SceneImporter.h/mm` — ufbx-based FBX loader: read meshes (uint32 indices, positions, normals, UVs, tangents), materials (texture paths), nodes (transforms)
- [x] **1.3** Flatten node hierarchy into instance list in SceneImporter
- [x] **1.4** Resolve texture paths relative to `Bistro_v5_2/Textures/`
- [x] **1.5** Generate tangents via ufbx if not present in FBX
- [x] **1.6** Log unsupported features (skeletal animation, morph targets) instead of silently ignoring
- [x] **1.7** Test: load `BistroExterior.fbx`, log mesh count, material count, instance count — verify data looks correct

**STOP — wait for user review before starting Phase 2.**

---

## Phase 2: Runtime Scene + Textures
_Goal: ImportedScene → engine-owned assets with loaded textures._

- [x] **2.1** Write `Scene/TextureAsset.h/mm` — wraps `id<MTLTexture>`
- [x] **2.2** Write `Scene/TextureCache.h/mm` — loads DDS via DDSLoader, TGA via MTKTextureLoader, deduplicates by path
- [x] **2.3** Write `Scene/MeshAsset.h/mm` — wraps imported mesh data, owns CPU-side arrays
- [x] **2.4** Write `Scene/MaterialAsset.h/mm` — resolved TextureAsset refs + PBR scalar parameters
- [x] **2.5** Write `Scene/SceneAsset.h/mm` — owns mesh/material/texture arrays + instance list + camera defaults
- [x] **2.6** Write conversion glue: `ImportedScene` → `SceneAsset` (SceneLoader.h/mm)
- [x] **2.7** Test: load all Bistro textures, log any missing/failed textures, verify material→texture linkage

**STOP — wait for user review before starting Phase 3.**

---

## Phase 3: GPU Upload + Acceleration Structures
_Goal: SceneAsset → GPU-resident data with BLAS/TLAS._

- [x] **3.1** Write `GPU/GPUScene.h/mm` — owns all GPU buffers (vertex, index, normal, UV, per-primitive, material, instance) + texture array + BLAS array + TLAS
- [x] **3.2** Write `GPU/SceneUploader.h/mm` — creates Metal buffers from SceneAsset, uploads vertex/index/material data
- [x] **3.3** Write `GPU/AccelerationStructureBuilder.h/mm` — extract BLAS/TLAS logic from Renderer.mm, generalize for GPUScene (one BLAS per unique mesh, TLAS from instance list, compaction)
- [x] **3.4** Add new files to Xcode targets
- [x] **3.5** Test: build BLAS/TLAS for Bistro without Metal validation errors, log triangle count and build time

**STOP — wait for user review before starting Phase 4.**

---

## Phase 4: Renderer Integration (First Bistro Pixels)
_Goal: See textured Bistro geometry on screen._

- [x] **4.1** Add `GPUMaterial`, `GPUTriangleData` structs to `ShaderTypes.h`
- [x] **4.2** Add GPUScene initializer to `Renderer.h/mm`
- [x] **4.3** Add GPUScene code path in Renderer: `createBistroPipelines`, `createBistroBuffers`, bistro resource binding in `drawInMTKView:`
- [x] **4.4** Modify `Shaders.metal`: add `bistroMode` function constant, read `GPUTriangleData` per-primitive data, interpolate normals/UVs, basic Lambertian with material base color and directional sun light
- [ ] **4.5** Wire `RenderOptionsGPU` into Uniforms: skip shadow rays if `!enableShadows` (deferred to Phase 7)
- [x] **4.6** Modify `ViewController.mm`: load Bistro via SceneImporter → SceneAsset → GPUScene → Renderer, with fallback to Cornell box
- [x] **4.7** Test: Bistro appears on screen with correct geometry and material colors

**STOP — wait for user review before starting Phase 5.**

---

## Phase 5: PBR Shading + Environment
_Goal: Correct physically-based appearance._

- [ ] **5.1** Add `evaluatePBR()` to shaders: GGX specular + Lambertian diffuse
- [ ] **5.2** Add `sampleNormalMap()`: TBN transform from interpolated tangent + normal
- [ ] **5.3** Read roughness/metalness from specular texture (R=AO, G=Roughness, B=Metalness)
- [ ] **5.4** Load and bind HDR environment map, sample on ray miss
- [ ] **5.5** Wire reflections toggle: skip bounce rays if `!enableReflections`
- [ ] **5.6** Add G-buffer output textures (depth R32Float, normal RGBA16Float, albedo RGBA8Unorm) and write them in shader
- [ ] **5.7** Test: PBR lighting correct, normal maps visible, environment in reflections

**STOP — wait for user review before starting Phase 6.**

---

## Phase 6: Camera Controls
_Goal: Navigate through Bistro interactively._

- [ ] **6.1** Write `Scene/CameraController.h/mm` — WASD + mouse look, produces Camera struct per frame
- [ ] **6.2** Forward keyboard/mouse events from ViewController to CameraController
- [ ] **6.3** Renderer reads Camera from CameraController each frame, resets `_frameIndex = 0` on camera move
- [ ] **6.4** Test: navigate through Bistro, accumulation restarts on movement

**STOP — wait for user review before starting Phase 7.**

---

## Phase 7: ImGui + RenderOptions
_Goal: GUI panel to toggle features at runtime._

- [ ] **7.1** Write `Application/ImGuiRenderer.h/mm` — wraps ImGui init, new frame, render encode (own render pass with loadAction:Load)
- [ ] **7.2** Integrate ImGuiRenderer in ViewController: init, event forwarding, per-frame calls
- [ ] **7.3** Add ImGui render pass in Renderer after copy/tone-map pass
- [ ] **7.4** Build settings panel: shadows toggle, reflections toggle, max bounces slider, accumulation toggle, exposure slider
- [ ] **7.5** Add debug view toggles: albedo, normals, depth
- [ ] **7.6** Add denoiser toggle (grayed out / placeholder)
- [ ] **7.7** Test: all toggles work, visual changes confirmed for each option

**STOP — wait for user review before starting Phase 8.**

---

## Phase 8: Denoiser Readiness (Architecture Only)
_Goal: Clean insertion point documented and verified._

- [ ] **8.1** Verify G-buffer textures written correctly via debug views
- [ ] **8.2** Document denoiser insertion point in code comments: compute pass slot between RT kernel and copy pass
- [ ] **8.3** Document expected denoiser interface: noisy color + depth + normal + albedo → denoised color
- [ ] **8.4** Verify accumulation targets and G-buffer textures have correct sizes/formats at all resolutions
- [ ] **8.5** Final acceptance checklist pass (see plan Section 6)

**DONE.**

---

## Acceptance Checklist (Final)

- [ ] Bistro exterior loads from `Bistro_v5_2/BistroExterior.fbx`
- [ ] Scene renders with PBR materials (base color, normal maps, roughness/metalness)
- [ ] WASD + mouse camera navigation works
- [ ] ImGui panel visible and functional
- [ ] Shadows toggle works (visible difference)
- [ ] Reflections toggle works (visible difference)
- [ ] Max bounces slider works (1-8)
- [ ] Accumulation toggle works
- [ ] `RenderOptions` is single source of truth
- [ ] G-buffer textures written by shader
- [ ] Debug views (albedo, normals, depth) work
- [ ] Denoiser insertion point documented
- [ ] Cornell box fallback still works
- [ ] `ufbx.h` not included outside `SceneImporter.mm`
- [ ] `imgui.h` not included outside `ImGuiRenderer.mm`
- [ ] Unsupported features documented, not silently hacked
- [ ] Builds on macOS 14+ (Metal 2 and Metal 3 targets)
