#pragma once

#include <simd/simd.h>
#include <string>
#include <vector>
#include <cstdint>

/// A single mesh extracted from the FBX file.
/// Contains triangle data with uint32 indices (Bistro has millions of triangles).
struct ImportedMesh {
    std::string name;
    std::vector<uint32_t> indices;
    std::vector<simd_float3> positions;
    std::vector<simd_float3> normals;
    std::vector<simd_float2> uvs;
    std::vector<simd_float4> tangents; // xyz = tangent direction, w = handedness sign
    uint32_t materialIndex = 0;
};

/// A material extracted from the FBX file.
/// Stores PBR parameters and texture file paths (relative to asset directory).
struct ImportedMaterial {
    std::string name;

    // Texture file paths (empty string = no texture)
    std::string baseColorTexturePath;
    std::string normalTexturePath;
    std::string specularTexturePath;   // ORM packed: R=AO, G=Roughness, B=Metalness
    std::string emissiveTexturePath;

    // Scalar fallback values when textures are absent
    simd_float3 baseColorFactor  = {1.0f, 1.0f, 1.0f};
    float       roughnessFactor  = 0.5f;
    float       metallicFactor   = 0.0f;
    simd_float3 emissiveFactor   = {0.0f, 0.0f, 0.0f};
    float       opacity          = 1.0f;
};

/// A node in the scene hierarchy.
struct ImportedNode {
    std::string name;
    simd_float4x4 localTransform;
    simd_float4x4 worldTransform;
    std::vector<uint32_t> meshIndices;      // indices into ImportedScene::meshes
    std::vector<uint32_t> childNodeIndices; // indices into ImportedScene::nodes
};

/// A flattened instance: a mesh placed at a world transform.
struct ImportedInstance {
    uint32_t meshIndex;
    simd_float4x4 worldTransform;
};

/// Complete imported scene data — plain C++ structs, no ObjC, no ufbx types.
struct ImportedScene {
    std::vector<ImportedMesh> meshes;
    std::vector<ImportedMaterial> materials;
    std::vector<ImportedNode> nodes;
    std::vector<ImportedInstance> instances;

    // Scene-level info
    simd_float3 boundsMin = {0, 0, 0};
    simd_float3 boundsMax = {0, 0, 0};

    // Summary for logging
    uint64_t totalTriangles = 0;
    uint64_t totalVertices  = 0;
};
