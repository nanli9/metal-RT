# CLAUDE.md

## Mission

This project is a Metal ray tracing demo being extended into a real scene viewer.

Current target:
- Load and render the `Bistro_v5_2` scene from its FBX-based asset folder
- Add a GUI for toggling ray traced features such as shadows and reflections
- Keep the code structure clean and explicitly extendable for a future denoiser

This is not a throwaway prototype. Favor a structure that can grow without turning into spaghetti.

---

## Non-negotiable rules

1. Do not write a custom raw FBX parser unless absolutely unavoidable.
   - Prefer a proven importer backend such as `ufbx`
   - `Assimp` is acceptable if it integrates more cleanly with the existing codebase
   - The renderer must not depend directly on FBX library types

2. Do not couple file format logic to rendering logic.
   - Import-time scene structures must be separate from runtime scene structures
   - Runtime scene structures must be separate from GPU resource ownership

3. Do not create a giant god object.
   - Avoid stuffing importer, scene graph, material system, UI, AS build, and rendering into one class

4. Do not hardcode feature toggles into scattered globals.
   - Centralize runtime toggles in a single render settings structure

5. Do not silently fake support for unsupported scene features.
   - If Bistro contains features not yet supported, document them clearly
   - Prefer explicit scope control over broken half-support

6. Minimize invasive edits.
   - Preserve the working demo where possible
   - Extend cleanly instead of rewriting blindly

---

## Current project goal

Implement a clean path from Bistro assets to ray traced rendering:

`FBX assets -> importer/backend -> imported scene -> engine/runtime scene -> GPU upload -> BLAS/TLAS -> RT render -> GUI-controlled options`

Initial supported scope should prioritize:
- static meshes
- transforms / hierarchy
- materials and texture path resolution
- mesh instances
- BLAS/TLAS construction
- camera navigation
- runtime toggles for shadows/reflections

Out of scope for first pass unless required by Bistro:
- skeletal animation
- morph targets
- skinning
- advanced FBX animation features
- full editor tooling
- full denoiser implementation

---

## Preferred architecture

### 1. Import layer

Create a strict importer boundary.

Suggested modules:
- `SceneImporter`
- `ImportedScene`
- `ImportedMesh`
- `ImportedMaterial`
- `ImportedTextureRef`
- `ImportedNode`

Responsibilities:
- read Bistro FBX and related asset references
- resolve transforms and hierarchy
- gather meshes, instances, materials, and texture references
- convert importer/backend data into engine-owned plain structures

Do not let renderer code depend on `ufbx` or `Assimp` types.

### 2. Runtime scene layer

Create engine/runtime scene structures that are format-agnostic.

Suggested modules:
- `Scene`
- `MeshAsset`
- `MaterialAsset`
- `TextureAsset`
- `SceneInstance`
- `SceneGraph` or flattened instance list

Responsibilities:
- own engine-side scene data
- remain independent from import library internals
- provide clean input to GPU upload and AS build

### 3. GPU scene layer

Suggested modules:
- `GPUScene`
- `SceneUploader`
- `AccelerationStructureBuilder`

Responsibilities:
- upload vertex/index/material/instance data
- create GPU buffers/textures
- build BLAS/TLAS
- maintain RT-visible scene resources

This layer should consume runtime scene data, not raw FBX data.

### 4. Render settings / GUI state

All GUI-controlled runtime features must live in a single structure.

Suggested shape:

```cpp
struct RenderOptions
{
    bool enableShadows = true;
    bool enableReflections = true;
    bool enableAccumulation = false;
    bool enableDenoiser = false;   // placeholder for future use
    int  maxBounces = 1;
    int  samplesPerPixel = 1;
};
```

---

## Implementation workflow

Implementation follows the phased plan in `CHECKLIST.md`. Progress is tracked by checking off sub-phases in that file.

**Phase-gating rule:** After completing each top-level phase (Phase 0, Phase 1, Phase 2, etc.), you MUST stop and let the user review the changes before proceeding to the next phase. Do not start a new phase without explicit user consent. You do NOT need to stop between sub-phases within the same phase unless the user specifically asks for that.

The full architectural plan is in `.claude/plans/majestic-knitting-allen.md`.
