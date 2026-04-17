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
- [x] **4.5** Wire `RenderOptionsGPU` into Uniforms: skip shadow rays if `!enableShadows`
- [x] **4.6** Modify `ViewController.mm`: load Bistro via SceneImporter → SceneAsset → GPUScene → Renderer, with fallback to Cornell box
- [x] **4.7** Test: Bistro appears on screen with correct geometry and material colors

**STOP — wait for user review before starting Phase 5.**

---

## Phase 5: Camera Controls
_Goal: Navigate through Bistro interactively._

- [x] **5.1** Write `Scene/CameraController.h/mm` — WASD + mouse look, produces Camera struct per frame
- [x] **5.2** Forward keyboard/mouse events from ViewController to CameraController
- [x] **5.3** Renderer reads Camera from CameraController each frame, resets `_frameIndex = 0` on camera move
- [x] **5.4** Test: navigate through Bistro, accumulation restarts on movement

**STOP — wait for user review before starting Phase 6.**

---

## Phase 6: PBR Shading + Environment
_Goal: Correct physically-based appearance._

- [x] **6.1** Add `evaluatePBR()` to shaders: GGX specular + Lambertian diffuse
- [x] **6.2** Add `sampleNormalMap()`: TBN transform from interpolated tangent + normal
- [x] **6.3** Read roughness/metalness from specular texture (R=AO, G=Roughness, B=Metalness)
- [x] **6.4** Load and bind HDR environment map, sample on ray miss
- [x] **6.5** Wire reflections toggle: skip bounce rays if `!enableReflections`
- [ ] **6.6** Add G-buffer output textures (depth R32Float, normal RGBA16Float, albedo RGBA8Unorm) and write them in shader (deferred to Phase 8)
- [x] **6.7** Test: PBR lighting with textures, normal maps, environment map
- [x] **6.8** (bonus) ImGui overlay with FPS counter
- [x] **6.9** Implement emissive light sources from FBX — materials with emissive textures/factors should emit light, making black emissive meshes (street lights, string lights, shop signs) glow in the scene

**STOP — wait for user review before starting Phase 7.**

---

## Phase 7: ImGui + RenderOptions
_Goal: GUI panel to toggle features at runtime._

- [x] **7.1** Write `Application/ImGuiRenderer.h/mm` — wraps ImGui init, new frame, render encode (own render pass with loadAction:Load)
- [x] **7.2** Integrate ImGuiRenderer in ViewController: init, event forwarding, per-frame calls
- [x] **7.3** Add ImGui render pass in Renderer after copy/tone-map pass
- [x] **7.4** Build settings panel: shadows toggle, reflections toggle, max bounces slider, accumulation toggle, exposure slider
- [x] **7.5** Add debug view toggles: albedo, normals, depth
- [x] **7.6** Add denoiser toggle (grayed out / placeholder)
- [x] **7.7** Test: all toggles work, visual changes confirmed for each option

**STOP — wait for user review before starting Phase 8.**

---

## Phase 8 Upper: A-trous Wavelet Denoiser
_Goal: Edge-aware spatial denoiser using G-buffer data, toggleable via ImGui._

- [x] **8.1** Create G-buffer textures in `Renderer.mm`: depth (`R32Float`), normals (`RGBA16Float`), albedo (`RGBA8Unorm`). Allocate in `mtkView:drawableSizeWillChange:` at viewport size.
- [x] **8.2** Write G-buffer data in shader at bounce 0. Add texture params at slots 3/4/5. Add debug modes 14 (Depth), 15 (GBuf Normal), 16 (GBuf Albedo). Bind textures in `Renderer.mm`. Add entries to ImGui debug combo.
- [x] **8.3** Replace `bool enableDenoiser` with `DenoiserMode` enum (Off/ATrous/SVGF) in `RenderOptions.h`. Add tuning params (iterations, sigmas). Update ImGui with combo box and sliders.
- [x] **8.4** Write `atrousDenoiser` compute kernel. Add `DenoiserParams` struct to `ShaderTypes.h`. 5x5 B3 spline wavelet kernel with edge-stopping functions. Create pipeline + ping-pong textures.
- [x] **8.5** Wire A-trous dispatch into rendering pipeline. Multi-pass with doubling step sizes (1,2,4,8,16), ping-pong between denoiser textures. Tone-map reads denoiser output when active.
- [x] **8.6** Add debug mode 17 "Denoise Weight". Conditional sigma sliders. Tune defaults for Bistro.

**STOP — wait for user review before starting Phase 8 Lower.**

---

## Phase 8 Lower: SVGF (Spatiotemporal Variance-Guided Filtering)
_Goal: Temporal reprojection + variance-guided filtering for superior denoising._

- [x] **8.11** Store view-projection matrices in Uniforms (current + previous + inverse). Add matrix helper functions. Add `denoiserMode` to Uniforms, skip accumulation when SVGF active.
- [x] **8.12** Write `computeMotionVectors` compute kernel. Reads G-buffer depth, reprojects via prev VP matrix, outputs to `RG16Float` texture. Add debug mode 18 "Motion Vectors".
- [x] **8.13** Allocate SVGF temporal textures: color history x2, moment history x2, history length, variance, prev G-buffer copies.
- [x] **8.14** Write `svgfTemporalAccumulation` kernel. Reproject, validate, blend with history.
- [x] **8.15** Write `svgfEstimateVariance` kernel. Compute variance from moments, spatial fallback for short history. Add debug mode 19 "SVGF Variance".
- [x] **8.16** Write `svgfAtrousFilter` kernel. Color sigma modulated by local variance. Same iterative dispatch as A-trous.
- [x] **8.17** Firefly clamping, G-buffer copy for prev frame, history reset on camera move, un-gray SVGF in ImGui.

**STOP — wait for user review before starting Phase 9.**

---

## Phase 9: ReSTIR DI (Direct Illumination)
_Goal: Reservoir-based spatiotemporal importance resampling for cleaner 1-spp direct lighting from many emissive lights._

### Sub-phase 9A: Data Structures & Initial Candidates
- [ ] **9.1** Define `Reservoir` struct in `ShaderTypes.h`: `lightSample` (position, normal, emission, triangleIndex), `weightSum` (streaming RIS weight), `M` (sample count), `W` (unbiased contribution weight). Keep it compact (≤64 bytes).
- [ ] **9.2** Add ReSTIR options to `RenderOptions.h`: `enableReSTIR` (bool), `restirTemporalMaxM` (int, default 20), `restirSpatialNeighbors` (int, default 5), `restirSpatialRadius` (float, default 30px).
- [ ] **9.3** Allocate reservoir textures/buffers in `Renderer.mm`: two reservoir buffers (temporal ping-pong, `width * height * sizeof(Reservoir)`), G-buffer shading data buffer (position, normal, albedo per pixel for MIS weight re-evaluation).
- [ ] **9.4** Write `restirInitialCandidates` compute kernel in `Shaders.metal`. For each pixel: generate N light candidates (N=32) via emissive triangle CDF (already exists in `_emissiveCDFBuffer`), evaluate target PDF `p_hat = Le * G * V_approx` (skip visibility for initial), apply streaming RIS (Talbot 2005) to keep one winning sample per pixel. Output to current reservoir buffer.

### Sub-phase 9B: Temporal Reuse
- [ ] **9.5** Write `restirTemporalReuse` kernel. Read motion vectors to find previous pixel, load previous reservoir. Validate: depth/normal consistency check (reuse existing thresholds from SVGF). Clamp previous `M` to `restirTemporalMaxM` to limit staleness. Combine current + previous reservoir via streaming RIS. Output merged reservoir.
- [ ] **9.6** Handle disocclusion: if temporal neighbor invalid, keep only current reservoir (M=1). Reset reservoirs on camera move (clear buffers).

### Sub-phase 9C: Spatial Reuse
- [ ] **9.7** Write `restirSpatialReuse` kernel. For each pixel, select `k` random neighbors within `restirSpatialRadius` pixels. For each neighbor: load its reservoir, re-evaluate target PDF `p_hat` at *current* pixel's shading point (Jacobian for solid angle change). Combine via streaming RIS. This is where the main quality boost comes from.
- [ ] **9.8** Visibility reuse check: trace shadow ray to validate the winning sample's visibility at the current pixel. Store final `W = (1/p_hat) * (1/M) * weightSum` for unbiased contribution weight.

### Sub-phase 9D: Integration & Controls
- [ ] **9.9** Integrate ReSTIR output into `raytracingKernel`. Replace inline NEE (emissive CDF sampling + shadow ray) with reservoir read when `enableReSTIR` is true. Final contribution = `reservoir.lightSample.emission * BRDF * G * reservoir.W`. Add `enableReSTIR` to Uniforms.
- [ ] **9.10** Dispatch order in `Renderer.mm`: RT kernel (with G-buffer write) → initial candidates → temporal reuse → spatial reuse → RT kernel reads reservoir for shading (or: two-pass approach where first pass writes G-buffer, second pass does shading with reservoir).
- [ ] **9.11** Wire ImGui controls: ReSTIR enable toggle, temporal M cap slider, spatial neighbor count slider, spatial radius slider. Add debug mode "ReSTIR Reservoir M" heatmap.
- [ ] **9.12** Test: compare 1-spp noise with ReSTIR on vs off. Verify temporal stability, no light leaking at depth discontinuities, proper reset on camera move.

**STOP — wait for user review before starting Phase 10.**

---

## Phase 10: MetalFX Temporal Upscaling
_Goal: Render at lower resolution, use MetalFX to upscale to display resolution._

- [x] **10.1** Link MetalFX.framework (weak). Runtime device support check. Add `enableMetalFXUpscaling`, `upscaleRatio` to `RenderOptions.h`. ImGui toggle.
- [x] **10.2** Add per-frame Halton sub-pixel jitter for TAA. Add `jitterX, jitterY, enableMetalFX` to Uniforms. Deterministic jitter in RT kernel when MetalFX active.
- [x] **10.3** Dual-resolution texture management. Internal vs display resolution. `_metalFXColorInput` (RGBA16Float), `_upscaledOutput` (RGBA16Float) at display res.
- [x] **10.4** Create `MTLFXTemporalScaler`. Format conversion (32F→16F) compute pass. Encode after denoiser. Tone-map reads upscaled output.
- [x] **10.5** ImGui controls: enable toggle, resolution ratio slider (0.25-1.0), internal/output resolution display. Texture reallocation on settings change.
- [x] **10.6** Resolution info display in ImGui when MetalFX active.

**STOP — wait for user review before starting Phase 11.**

---

## Phase 11: Bloom + Tone Mapping Post-Processing
_Goal: Replace basic Reinhard with proper HDR post-processing pipeline: bloom extraction, blur, composite, and filmic tone mapping._

### Sub-phase 11A: Tone Mapping Upgrade
- [x] **11.1** Add tone mapping mode to `RenderOptions.h`: `ToneMapMode` enum (Reinhard, ACES, AgX), `toneMapMode` field. Keep existing `exposureAdjust`.
- [x] **11.2** Implement ACES filmic tone mapping in `copyFragment` (or new `tonemapFragment`). Use the fitted ACES curve (Stephen Hill's approximation). Add AgX as a neutral-look alternative. Select via `toneMapMode` uniform.
- [x] **11.3** Wire tone map mode combo in ImGui. Expose exposure slider (already exists). Test: compare Reinhard vs ACES vs AgX on Sponza — ACES should have richer highlights and deeper shadows.

### Sub-phase 11B: Bloom
- [x] **11.4** Add bloom options to `RenderOptions.h`: `enableBloom` (bool), `bloomThreshold` (float, default 1.0), `bloomIntensity` (float, default 0.05), `bloomRadius` (int, default 6 mip levels).
- [x] **11.5** Allocate bloom textures in `Renderer.mm`: mip chain (6 levels, each half-resolution of previous), `RGBA16Float` format. Two textures per mip level for ping-pong blur.
- [x] **11.6** Write `bloomThreshold` compute kernel: extract pixels above `bloomThreshold` luminance from the HDR color buffer (pre-tonemap). Output to mip 0 of bloom chain.
- [x] **11.7** Write `bloomDownsample` compute kernel: 13-tap tent filter (Karis average for mip 0 to prevent firefly bloom). Progressive downsample through mip chain.
- [x] **11.8** Write `bloomUpsample` compute kernel: 9-tap tent filter upsampling with additive blend. Progressive upsample from smallest mip back to full resolution.
- [x] **11.9** Write `bloomComposite` pass: add `bloomResult * bloomIntensity` to HDR color before tone mapping. Can be folded into the tone-map fragment shader.
- [x] **11.10** Wire bloom controls in ImGui: enable toggle, threshold slider (0.0-5.0), intensity slider (0.0-0.5), debug mode "Bloom Only" to visualize bloom contribution.
- [x] **11.11** Test: bright emissive surfaces and specular highlights should produce soft glow. Verify no firefly bloom artifacts. Performance: bloom should add <1ms.

**STOP — wait for user review.**

---

## Phase 12: Gamma Correction + HDR Display
_Goal: Fix sRGB input/output pipeline and enable Extended Dynamic Range._

### Sub-phase 12A: sRGB Texture Input
- [x] **12.1** Add `sRGB:` parameter to DDSLoader — BC1_sRGB, BC3_sRGB format variants
- [x] **12.2** Add `sRGB:` parameter to TextureCache — sRGB-aware cache keys, forward to DDSLoader/MTKTextureLoader
- [x] **12.3** Load baseColor and emissive textures as sRGB, normal and specular as linear, in SceneLoader
- [x] **12.4** Test: albedo debug view shows brighter/more vivid colors; normals unchanged

### Sub-phase 12B: sRGB Output Encoding
- [x] **12.5** Add `linearToSRGB()` function to Shaders.metal (piecewise IEC 61966-2-1)
- [x] **12.6** Apply sRGB OETF in `copyFragment` after tone mapping
- [x] **12.7** Test: scene brightness correct; ImGui overlay renders correctly

### Sub-phase 12C: HDR / Extended Dynamic Range
- [x] **12.8** Add `enableHDR`, `hdrHeadroom` to RenderOptions and Uniforms
- [x] **12.9** Enable `wantsExtendedDynamicRangeContent` on CAMetalLayer, set sRGB colorspace
- [x] **12.10** Query `maximumExtendedDynamicRangeColorComponentValue` per frame in ViewController
- [x] **12.11** Implement HDR-aware tone mapping (extended Reinhard with variable white point)
- [x] **12.12** Wire HDR fields through ToneMapParams struct and Renderer.mm updateUniforms
- [x] **12.13** Add ImGui HDR controls (enable toggle, headroom display)
- [x] **12.14** Test: HDR highlights exceed SDR white on EDR displays; SDR fallback works

**STOP — wait for user review.**

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
- [ ] G-buffer textures written by shader (depth, normals, albedo)
- [ ] Debug views (albedo, normals, depth, G-buffer, motion vectors, variance) work
- [ ] A-trous denoiser toggleable and functional
- [ ] SVGF denoiser toggleable and functional
- [ ] Denoiser mode combo: Off / A-Trous / SVGF
- [ ] ReSTIR DI improves emissive light sampling quality (less 1-spp noise)
- [ ] MetalFX temporal upscaling works at configurable ratios
- [ ] Bloom extracts bright areas, produces soft glow on emissives/specular
- [ ] Tone mapping selectable: Reinhard / ACES / AgX
- [ ] sRGB input: color textures (baseColor, emissive) loaded with sRGB formats
- [ ] sRGB output: linearToSRGB encoding applied after tone mapping
- [ ] HDR/EDR: highlights exceed SDR white on EDR displays when enabled
- [ ] Cornell box fallback still works
- [ ] `ufbx.h` not included outside `SceneImporter.mm`
- [ ] `imgui.h` not included outside `ImGuiRenderer.mm`
- [ ] Unsupported features documented, not silently hacked
- [ ] Builds on macOS 14+ (Metal 2 and Metal 3 targets)
