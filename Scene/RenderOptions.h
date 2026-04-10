#pragma once

/// Denoiser mode selection
enum class DenoiserMode : int
{
    Off    = 0,
    ATrous = 1,
    SVGF   = 2
};

/// Centralized render settings structure.
/// This is the single source of truth for all GUI-controlled runtime features.
/// The GUI reads and writes this struct; the renderer copies relevant fields
/// into the per-frame Uniforms buffer for shader consumption.
struct RenderOptions
{
    bool enablePBR          = true;
    bool enableShadows      = true;
    bool enableReflections  = true;
    bool enableAccumulation = true;
    DenoiserMode denoiserMode = DenoiserMode::Off;
    int  maxBounces         = 3;
    int  debugMode          = 0;
    float emissiveIntensity = 5.0f;
    float exposureAdjust    = 0.0f;   // EV stops, applied in tonemapping

    // A-trous / SVGF denoiser tuning
    int   atrousIterations    = 5;      // number of filter passes (1-5)
    float denoiseSigmaColor   = 1.0f;   // luminance edge-stopping strength
    float denoiseSigmaNormal  = 128.0f; // normal edge-stopping strength
    float denoiseSigmaDepth   = 1.0f;   // depth edge-stopping strength
};
