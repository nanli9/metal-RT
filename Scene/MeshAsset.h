#pragma once

#include <simd/simd.h>
#include <string>
#include <vector>
#include <cstdint>

/// Engine-owned mesh data. Format-agnostic — no dependency on import layer.
struct MeshAsset {
    std::string name;
    std::vector<uint32_t> indices;
    std::vector<simd_float3> positions;
    std::vector<simd_float3> normals;
    std::vector<simd_float2> uvs;
    std::vector<simd_float4> tangents; // xyz = direction, w = handedness
    uint32_t materialIndex = 0;

    uint32_t triangleCount() const { return (uint32_t)(indices.size() / 3); }
    uint32_t vertexCount() const { return (uint32_t)positions.size(); }
};
