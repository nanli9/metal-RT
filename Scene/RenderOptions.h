#pragma once

/// Centralized render settings structure.
/// This is the single source of truth for all GUI-controlled runtime features.
/// The GUI reads and writes this struct; the renderer copies relevant fields
/// into the per-frame Uniforms buffer for shader consumption.
struct RenderOptions
{
    bool enableShadows      = true;
    bool enableReflections  = true;
    bool enableAccumulation = true;
    bool enableDenoiser     = false;  // placeholder for future use
    int  maxBounces         = 3;
    int  samplesPerPixel    = 1;
    bool showAlbedo         = false;  // debug view
    bool showNormals        = false;  // debug view
    bool showDepth          = false;  // debug view
    float exposureAdjust    = 0.0f;
};
