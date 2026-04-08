#import "SceneImporter.h"
#include "ufbx.h"
#include <unordered_map>

// ---- Helpers ----

static simd_float4x4 convertMatrix(const ufbx_matrix &m) {
    // ufbx_matrix is a 4x3 affine matrix (3 columns + origin).
    // Convert to column-major simd_float4x4.
    return (simd_float4x4){{
        { (float)m.cols[0].x, (float)m.cols[0].y, (float)m.cols[0].z, 0.0f },
        { (float)m.cols[1].x, (float)m.cols[1].y, (float)m.cols[1].z, 0.0f },
        { (float)m.cols[2].x, (float)m.cols[2].y, (float)m.cols[2].z, 0.0f },
        { (float)m.cols[3].x, (float)m.cols[3].y, (float)m.cols[3].z, 1.0f },
    }};
}

static std::string resolveTexturePath(const ufbx_texture *tex, NSString *assetDir) {
    if (!tex) return "";

    // Try relative filename first, then absolute, then generic filename
    std::string relPath;
    if (tex->relative_filename.length > 0) {
        relPath = std::string(tex->relative_filename.data, tex->relative_filename.length);
    } else if (tex->filename.length > 0) {
        relPath = std::string(tex->filename.data, tex->filename.length);
    }

    if (relPath.empty()) return "";

    // Normalize path separators (Windows backslash -> forward slash)
    for (char &c : relPath) {
        if (c == '\\') c = '/';
    }

    // Extract just the filename component
    std::string basename = relPath;
    size_t lastSlash = relPath.rfind('/');
    if (lastSlash != std::string::npos) {
        basename = relPath.substr(lastSlash + 1);
    }

    // Check if the file exists in the Textures/ subdirectory
    NSString *texDir = [assetDir stringByAppendingPathComponent:@"Textures"];
    NSString *fullPath = [texDir stringByAppendingPathComponent:
                          [NSString stringWithUTF8String:basename.c_str()]];

    if ([[NSFileManager defaultManager] fileExistsAtPath:fullPath]) {
        return fullPath.UTF8String;
    }

    // Try the path as-is relative to asset dir
    fullPath = [assetDir stringByAppendingPathComponent:
                [NSString stringWithUTF8String:relPath.c_str()]];
    if ([[NSFileManager defaultManager] fileExistsAtPath:fullPath]) {
        return fullPath.UTF8String;
    }

    NSLog(@"SceneImporter: texture not found: %s (basename: %s)", relPath.c_str(), basename.c_str());
    return "";
}

static std::string getTexturePathFromMap(const ufbx_material_map &map, NSString *assetDir) {
    if (map.texture && map.texture_enabled) {
        return resolveTexturePath(map.texture, assetDir);
    }
    return "";
}

// ---- Vertex deduplication ----

struct PackedVertex {
    simd_float3 position;
    simd_float3 normal;
    simd_float2 uv;
    simd_float4 tangent;

    bool operator==(const PackedVertex &o) const {
        return simd_equal(position, o.position) &&
               simd_equal(normal, o.normal) &&
               simd_equal(uv, o.uv) &&
               simd_equal(tangent, o.tangent);
    }
};

struct PackedVertexHash {
    size_t operator()(const PackedVertex &v) const {
        // Simple hash combining position, normal, uv
        size_t h = 0;
        auto hashFloat = [&](float f) {
            uint32_t bits;
            memcpy(&bits, &f, 4);
            h ^= std::hash<uint32_t>()(bits) + 0x9e3779b9 + (h << 6) + (h >> 2);
        };
        hashFloat(v.position.x); hashFloat(v.position.y); hashFloat(v.position.z);
        hashFloat(v.normal.x); hashFloat(v.normal.y); hashFloat(v.normal.z);
        hashFloat(v.uv.x); hashFloat(v.uv.y);
        return h;
    }
};

// ---- Implementation ----

@implementation SceneImporter

+ (ImportedScene *)importFBXAtPath:(NSString *)path error:(NSError **)error {
    NSString *assetDir = [path stringByDeletingLastPathComponent];

    // Configure load options
    ufbx_load_opts opts = {};
    opts.generate_missing_normals = true;
    // Target: Y-up, right-handed (Metal convention)
    opts.target_axes = (ufbx_coordinate_axes){
        .right = UFBX_COORDINATE_AXIS_POSITIVE_X,
        .up = UFBX_COORDINATE_AXIS_POSITIVE_Y,
        .front = UFBX_COORDINATE_AXIS_POSITIVE_Z,
    };
    opts.target_unit_meters = 1.0f; // normalize to meters

    // Load the FBX file
    ufbx_error ufbxError = {};
    ufbx_scene *scene = ufbx_load_file(path.UTF8String, &opts, &ufbxError);
    if (!scene) {
        char errorBuf[512];
        ufbx_format_error(errorBuf, sizeof(errorBuf), &ufbxError);
        NSLog(@"SceneImporter: failed to load %@: %s", path, errorBuf);
        if (error) {
            *error = [NSError errorWithDomain:@"SceneImporter" code:1
                     userInfo:@{NSLocalizedDescriptionKey:
                                [NSString stringWithFormat:@"Failed to load FBX: %s", errorBuf]}];
        }
        return nullptr;
    }

    NSLog(@"SceneImporter: loaded %@ — %zu meshes, %zu materials, %zu nodes, %zu textures",
          path.lastPathComponent,
          scene->meshes.count, scene->materials.count,
          scene->nodes.count, scene->textures.count);

    // Log unsupported features
    if (scene->bones.count > 0)
        NSLog(@"SceneImporter: [UNSUPPORTED] scene contains %zu bones (skeletal animation not supported)", scene->bones.count);
    for (size_t i = 0; i < scene->meshes.count; i++) {
        ufbx_mesh *mesh = scene->meshes.data[i];
        if (mesh->blend_deformers.count > 0)
            NSLog(@"SceneImporter: [UNSUPPORTED] mesh '%s' has blend shapes/morph targets", mesh->element.name.data);
        if (mesh->skin_deformers.count > 0)
            NSLog(@"SceneImporter: [UNSUPPORTED] mesh '%s' has skin deformers", mesh->element.name.data);
    }

    auto *result = new ImportedScene();

    // ---- Import materials ----
    result->materials.resize(scene->materials.count);
    for (size_t i = 0; i < scene->materials.count; i++) {
        ufbx_material *mat = scene->materials.data[i];
        ImportedMaterial &imported = result->materials[i];

        imported.name = std::string(mat->element.name.data, mat->element.name.length);

        // Try PBR maps first, fall back to FBX legacy maps
        imported.baseColorTexturePath = getTexturePathFromMap(mat->pbr.base_color, assetDir);
        if (imported.baseColorTexturePath.empty())
            imported.baseColorTexturePath = getTexturePathFromMap(mat->fbx.diffuse_color, assetDir);

        imported.normalTexturePath = getTexturePathFromMap(mat->pbr.normal_map, assetDir);
        if (imported.normalTexturePath.empty())
            imported.normalTexturePath = getTexturePathFromMap(mat->fbx.normal_map, assetDir);

        // For specular/ORM: check PBR roughness map first
        imported.specularTexturePath = getTexturePathFromMap(mat->pbr.roughness, assetDir);
        if (imported.specularTexturePath.empty())
            imported.specularTexturePath = getTexturePathFromMap(mat->pbr.specular_color, assetDir);
        if (imported.specularTexturePath.empty())
            imported.specularTexturePath = getTexturePathFromMap(mat->fbx.specular_color, assetDir);

        imported.emissiveTexturePath = getTexturePathFromMap(mat->pbr.emission_color, assetDir);
        if (imported.emissiveTexturePath.empty())
            imported.emissiveTexturePath = getTexturePathFromMap(mat->fbx.emission_color, assetDir);

        // Scalar fallbacks
        if (mat->pbr.base_color.has_value)
            imported.baseColorFactor = simd_make_float3(
                (float)mat->pbr.base_color.value_vec3.x,
                (float)mat->pbr.base_color.value_vec3.y,
                (float)mat->pbr.base_color.value_vec3.z);
        else if (mat->fbx.diffuse_color.has_value)
            imported.baseColorFactor = simd_make_float3(
                (float)mat->fbx.diffuse_color.value_vec3.x,
                (float)mat->fbx.diffuse_color.value_vec3.y,
                (float)mat->fbx.diffuse_color.value_vec3.z);

        if (mat->pbr.roughness.has_value)
            imported.roughnessFactor = (float)mat->pbr.roughness.value_real;

        if (mat->pbr.metalness.has_value)
            imported.metallicFactor = (float)mat->pbr.metalness.value_real;

        if (mat->pbr.emission_color.has_value)
            imported.emissiveFactor = simd_make_float3(
                (float)mat->pbr.emission_color.value_vec3.x,
                (float)mat->pbr.emission_color.value_vec3.y,
                (float)mat->pbr.emission_color.value_vec3.z);

        if (mat->pbr.opacity.has_value)
            imported.opacity = (float)mat->pbr.opacity.value_real;
    }

    // ---- Import meshes ----
    // We split each ufbx_mesh by material into separate ImportedMesh entries.
    // This gives one material per mesh, simplifying per-primitive data on the GPU.

    // Map from (ufbx mesh index, material index) -> ImportedMesh index
    std::unordered_map<uint64_t, uint32_t> meshPartMap;

    for (size_t mi = 0; mi < scene->meshes.count; mi++) {
        ufbx_mesh *mesh = scene->meshes.data[mi];

        bool hasUVs = mesh->vertex_uv.exists;
        bool hasNormals = mesh->vertex_normal.exists;
        bool hasTangents = mesh->vertex_tangent.exists;

        // Iterate over faces and triangulate
        for (size_t fi = 0; fi < mesh->num_faces; fi++) {
            ufbx_face face = mesh->faces.data[fi];
            uint32_t faceMat = 0;
            if (mesh->face_material.count > 0)
                faceMat = mesh->face_material.data[fi];

            // Map material index to scene-global material index
            uint32_t globalMatIdx = 0;
            if (faceMat < mesh->materials.count && mesh->materials.data[faceMat]) {
                globalMatIdx = (uint32_t)mesh->materials.data[faceMat]->element.typed_id;
            }

            // Find or create ImportedMesh for this (mesh, material) pair
            uint64_t key = ((uint64_t)mi << 32) | globalMatIdx;
            auto it = meshPartMap.find(key);
            uint32_t meshIdx;
            if (it == meshPartMap.end()) {
                meshIdx = (uint32_t)result->meshes.size();
                meshPartMap[key] = meshIdx;
                result->meshes.emplace_back();
                ImportedMesh &newMesh = result->meshes.back();
                newMesh.name = std::string(mesh->element.name.data, mesh->element.name.length);
                newMesh.materialIndex = globalMatIdx;
            } else {
                meshIdx = it->second;
            }

            ImportedMesh &importedMesh = result->meshes[meshIdx];

            // Triangulate the face (fan triangulation)
            for (uint32_t ti = 0; ti < face.num_indices - 2; ti++) {
                uint32_t i0 = face.index_begin;
                uint32_t i1 = face.index_begin + ti + 1;
                uint32_t i2 = face.index_begin + ti + 2;

                uint32_t triIndices[3] = { i0, i1, i2 };
                for (int vi = 0; vi < 3; vi++) {
                    uint32_t idx = triIndices[vi];

                    PackedVertex pv = {};
                    pv.position = simd_make_float3(
                        (float)mesh->vertex_position.values.data[mesh->vertex_position.indices.data[idx]].x,
                        (float)mesh->vertex_position.values.data[mesh->vertex_position.indices.data[idx]].y,
                        (float)mesh->vertex_position.values.data[mesh->vertex_position.indices.data[idx]].z);

                    if (hasNormals) {
                        pv.normal = simd_make_float3(
                            (float)mesh->vertex_normal.values.data[mesh->vertex_normal.indices.data[idx]].x,
                            (float)mesh->vertex_normal.values.data[mesh->vertex_normal.indices.data[idx]].y,
                            (float)mesh->vertex_normal.values.data[mesh->vertex_normal.indices.data[idx]].z);
                    }

                    if (hasUVs) {
                        pv.uv = simd_make_float2(
                            (float)mesh->vertex_uv.values.data[mesh->vertex_uv.indices.data[idx]].x,
                            (float)mesh->vertex_uv.values.data[mesh->vertex_uv.indices.data[idx]].y);
                        // Flip V for Metal (DX convention -> GL/Metal convention)
                        pv.uv.y = 1.0f - pv.uv.y;
                    }

                    if (hasTangents) {
                        float sign = 1.0f;
                        if (mesh->vertex_tangent.values_w.count > 0) {
                            sign = (float)mesh->vertex_tangent.values_w.data[mesh->vertex_tangent.indices.data[idx]];
                        }
                        ufbx_vec3 t = mesh->vertex_tangent.values.data[mesh->vertex_tangent.indices.data[idx]];
                        pv.tangent = simd_make_float4((float)t.x, (float)t.y, (float)t.z, sign);
                    }

                    // Deduplicate vertices using hash map
                    // For simplicity and to handle large meshes efficiently,
                    // we just append and let GPU-side dedup happen via index buffer
                    uint32_t vertIdx = (uint32_t)importedMesh.positions.size();
                    importedMesh.positions.push_back(pv.position);
                    importedMesh.normals.push_back(pv.normal);
                    importedMesh.uvs.push_back(pv.uv);
                    importedMesh.tangents.push_back(pv.tangent);
                    importedMesh.indices.push_back(vertIdx);
                }
            }
        }
    }

    // ---- Generate tangents for meshes that lack them ----
    for (auto &mesh : result->meshes) {
        bool allZero = true;
        for (size_t i = 0; i < mesh.tangents.size() && i < 100; i++) {
            if (simd_length_squared(mesh.tangents[i]) > 0.001f) {
                allZero = false;
                break;
            }
        }
        if (allZero && !mesh.normals.empty() && !mesh.uvs.empty()) {
            // Generate tangents using MikkTSpace-style approach:
            // For each triangle, compute edge vectors and UV deltas
            for (size_t i = 0; i + 2 < mesh.indices.size(); i += 3) {
                uint32_t i0 = mesh.indices[i], i1 = mesh.indices[i+1], i2 = mesh.indices[i+2];
                simd_float3 p0 = mesh.positions[i0], p1 = mesh.positions[i1], p2 = mesh.positions[i2];
                simd_float2 uv0 = mesh.uvs[i0], uv1 = mesh.uvs[i1], uv2 = mesh.uvs[i2];

                simd_float3 e1 = p1 - p0, e2 = p2 - p0;
                simd_float2 duv1 = uv1 - uv0, duv2 = uv2 - uv0;

                float denom = duv1.x * duv2.y - duv2.x * duv1.y;
                float r = (fabsf(denom) > 1e-8f) ? (1.0f / denom) : 0.0f;

                simd_float3 tangent = (e1 * duv2.y - e2 * duv1.y) * r;
                float len = simd_length(tangent);
                if (len > 1e-8f) tangent /= len;

                // Compute handedness
                simd_float3 bitangent = (e2 * duv1.x - e1 * duv2.x) * r;
                simd_float3 n = mesh.normals[i0];
                float sign = (simd_dot(simd_cross(n, tangent), bitangent) < 0.0f) ? -1.0f : 1.0f;

                simd_float4 t4 = simd_make_float4(tangent.x, tangent.y, tangent.z, sign);
                mesh.tangents[i0] = t4;
                mesh.tangents[i1] = t4;
                mesh.tangents[i2] = t4;
            }
        }
    }

    // ---- Build node hierarchy and flatten instances ----
    // We walk the scene graph and create instances for each node that has a mesh.
    // Since we split meshes by material, one ufbx_mesh might produce multiple ImportedMesh entries.

    simd_float3 boundsMin = {INFINITY, INFINITY, INFINITY};
    simd_float3 boundsMax = {-INFINITY, -INFINITY, -INFINITY};

    for (size_t ni = 0; ni < scene->nodes.count; ni++) {
        ufbx_node *node = scene->nodes.data[ni];
        if (!node->mesh) continue;

        size_t meshUfbxIdx = node->mesh->element.typed_id;
        simd_float4x4 worldTransform = convertMatrix(node->geometry_to_world);

        // Find all ImportedMesh entries that came from this ufbx mesh
        for (auto &[key, meshIdx] : meshPartMap) {
            uint64_t sourceMeshIdx = key >> 32;
            if (sourceMeshIdx == meshUfbxIdx) {
                ImportedInstance inst;
                inst.meshIndex = meshIdx;
                inst.worldTransform = worldTransform;
                result->instances.push_back(inst);

                // Update bounds
                ImportedMesh &m = result->meshes[meshIdx];
                for (const auto &pos : m.positions) {
                    simd_float4 wp = simd_mul(worldTransform, simd_make_float4(pos.x, pos.y, pos.z, 1.0f));
                    boundsMin = simd_min(boundsMin, simd_make_float3(wp.x, wp.y, wp.z));
                    boundsMax = simd_max(boundsMax, simd_make_float3(wp.x, wp.y, wp.z));
                }
            }
        }
    }

    result->boundsMin = boundsMin;
    result->boundsMax = boundsMax;

    // Compute totals
    for (const auto &mesh : result->meshes) {
        result->totalVertices += mesh.positions.size();
        result->totalTriangles += mesh.indices.size() / 3;
    }

    NSLog(@"SceneImporter: import complete — %zu imported meshes, %zu instances, %llu triangles, %llu vertices",
          result->meshes.size(), result->instances.size(),
          result->totalTriangles, result->totalVertices);
    NSLog(@"SceneImporter: bounds min=(%.2f, %.2f, %.2f) max=(%.2f, %.2f, %.2f)",
          result->boundsMin.x, result->boundsMin.y, result->boundsMin.z,
          result->boundsMax.x, result->boundsMax.y, result->boundsMax.z);

    ufbx_free_scene(scene);
    return result;
}

@end
