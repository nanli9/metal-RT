#include "ImportedScene.h"

ImportedScene *mergeImportedScenes(const ImportedScene &a, const ImportedScene &b) {
    auto *merged = new ImportedScene();

    const uint32_t materialOffset = (uint32_t)a.materials.size();
    const uint32_t meshOffset     = (uint32_t)a.meshes.size();
    const uint32_t nodeOffset     = (uint32_t)a.nodes.size();

    // Materials: concatenate A then B (no remapping needed)
    merged->materials.reserve(a.materials.size() + b.materials.size());
    merged->materials.insert(merged->materials.end(), a.materials.begin(), a.materials.end());
    merged->materials.insert(merged->materials.end(), b.materials.begin(), b.materials.end());

    // Meshes: concatenate A then B, remap B's materialIndex
    merged->meshes.reserve(a.meshes.size() + b.meshes.size());
    merged->meshes.insert(merged->meshes.end(), a.meshes.begin(), a.meshes.end());
    for (const auto &mesh : b.meshes) {
        merged->meshes.push_back(mesh);
        merged->meshes.back().materialIndex += materialOffset;
    }

    // Instances: concatenate A then B, remap B's meshIndex
    merged->instances.reserve(a.instances.size() + b.instances.size());
    merged->instances.insert(merged->instances.end(), a.instances.begin(), a.instances.end());
    for (const auto &inst : b.instances) {
        ImportedInstance remapped = inst;
        remapped.meshIndex += meshOffset;
        merged->instances.push_back(remapped);
    }

    // Nodes: concatenate A then B, remap B's child/mesh indices
    merged->nodes.reserve(a.nodes.size() + b.nodes.size());
    merged->nodes.insert(merged->nodes.end(), a.nodes.begin(), a.nodes.end());
    for (const auto &node : b.nodes) {
        ImportedNode remapped = node;
        for (auto &mi : remapped.meshIndices)      mi += meshOffset;
        for (auto &ci : remapped.childNodeIndices)  ci += nodeOffset;
        merged->nodes.push_back(std::move(remapped));
    }

    // Bounds: union
    merged->boundsMin = simd_min(a.boundsMin, b.boundsMin);
    merged->boundsMax = simd_max(a.boundsMax, b.boundsMax);

    // Totals
    merged->totalTriangles = a.totalTriangles + b.totalTriangles;
    merged->totalVertices  = a.totalVertices  + b.totalVertices;

    return merged;
}
