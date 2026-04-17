/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The header that contains the types and enumeration constants that the Metal shaders and the C/Objective-C source share.
*/

#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

#define GEOMETRY_MASK_TRIANGLE 1
#define GEOMETRY_MASK_SPHERE   2
#define GEOMETRY_MASK_LIGHT    4

#define GEOMETRY_MASK_GEOMETRY (GEOMETRY_MASK_TRIANGLE | GEOMETRY_MASK_SPHERE)

#define RAY_MASK_PRIMARY   (GEOMETRY_MASK_GEOMETRY | GEOMETRY_MASK_LIGHT)
#define RAY_MASK_SHADOW    GEOMETRY_MASK_GEOMETRY
#define RAY_MASK_SECONDARY GEOMETRY_MASK_GEOMETRY

#ifndef __METAL_VERSION__
struct packed_float3 {
#ifdef __cplusplus
    packed_float3() = default;
    packed_float3(vector_float3 v) : x(v.x), y(v.y), z(v.z) {}
#endif
    float x;
    float y;
    float z;
};
#endif

struct Camera {
    vector_float3 position;
    vector_float3 right;
    vector_float3 up;
    vector_float3 forward;
};

struct AreaLight {
    vector_float3 position;
    vector_float3 forward;
    vector_float3 right;
    vector_float3 up;
    vector_float3 color;
};

struct Uniforms {
    unsigned int width;
    unsigned int height;
    unsigned int frameIndex;
    unsigned int lightCount;
    unsigned int enablePBR;  // 0 = flat shading (Phase 4), 1 = full PBR
    unsigned int debugMode;
    unsigned int maxBounces;
    unsigned int emissiveLightCount;
    float emissiveIntensity;
    float emissiveTotalWeight; // sum of all emissive triangle weights for PDF
    unsigned int enableShadows;
    unsigned int enableReflections;
    unsigned int denoiserMode; // 0=Off, 1=ATrous, 2=SVGF
    unsigned int enableMetalFX; // 0=off, 1=on (use deterministic jitter)
    float jitterX;  // sub-pixel jitter in pixel units [-0.5, 0.5]
    float jitterY;
    float svgfAlphaColor;    // SVGF temporal alpha floor
    float svgfHistoryMax;    // SVGF history length cap
    Camera camera;
    matrix_float4x4 viewProjectionMatrix;
    matrix_float4x4 prevViewProjectionMatrix;
    matrix_float4x4 inverseViewProjectionMatrix;
};

struct Sphere {
    packed_float3 origin;
    float radiusSquared;
    packed_float3 color;
    float radius;
};

struct Triangle {
    vector_float3 normals[3];
    vector_float3 colors[3];
};

// ---- GPU scene types (used by Bistro path) ----
// These use plain float arrays for cross-platform (CPU + Metal shader) compatibility.

struct GPUTriangleData {
    float normals[3][3];    // 3 vertices * xyz
    float uvs[3][2];        // 3 vertices * uv
    float tangents[3][3];   // 3 vertices * xyz
    float tangentSign[3];
    unsigned int materialIndex;
};

struct GPUEmissiveTriangle {
    float v0[3], v1[3], v2[3]; // world-space vertex positions
    float normal[3];            // face normal
    float emissiveColor[3];     // pre-multiplied emissive color
    float area;                 // triangle area in world space
    float cdfValue;             // cumulative distribution value [0..1]
};

struct GPUMaterial {
    float baseColorFactor[3];
    float roughnessFactor;
    float metallicFactor;
    float opacity;
    float emissiveFactor[3];
    unsigned int baseColorTextureIndex;
    unsigned int normalTextureIndex;
    unsigned int specularTextureIndex;   // ORM packed
    unsigned int emissiveTextureIndex;
};

// ---- Denoiser types ----

struct DenoiserParams {
    unsigned int stepSize;      // 1, 2, 4, 8, 16 for each A-trous iteration
    float sigmaColor;           // luminance edge-stopping weight
    float sigmaNormal;          // normal edge-stopping weight
    float sigmaDepth;           // depth edge-stopping weight
    unsigned int width;
    unsigned int height;
    float temporalBlend;        // 0..1: how much to blend toward unfiltered (0=full denoise, 1=no denoise)
    unsigned int isLastIteration; // 1 if this is the final A-trous pass
    unsigned int iterationIndex;  // 0-based A-trous iteration index
};

#endif
