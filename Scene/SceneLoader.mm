#import "SceneLoader.h"
#import "SceneAsset.h"
#import "MaterialAsset.h"
#import "TextureAsset.h"
#import "TextureCache.h"
#import "MeshAsset.h"
#import "SceneImporter.h"
#import "ImportedScene.h"

@implementation SceneLoader

/// Convert an ImportedScene into a SceneAsset. Takes ownership of `imported` (deletes it).
+ (SceneAsset *)_buildSceneAssetFromImported:(ImportedScene *)imported
                                      device:(id<MTLDevice>)device {
    // Load textures
    NSLog(@"SceneLoader: loading textures...");
    TextureCache *texCache = [[TextureCache alloc] initWithDevice:device];

    // Convert materials
    NSMutableArray<MaterialAsset *> *materials = [NSMutableArray new];
    for (const auto &importedMat : imported->materials) {
        MaterialAsset *mat = [[MaterialAsset alloc] init];
        mat.name = [NSString stringWithUTF8String:importedMat.name.c_str()];

        // Resolve textures via cache
        // Color textures (baseColor, emissive) use sRGB formats for hardware auto-linearization.
        // Data textures (normal, specular/ORM) remain linear.
        if (!importedMat.baseColorTexturePath.empty()) {
            mat.baseColorTexture = [texCache textureAtPath:
                [NSString stringWithUTF8String:importedMat.baseColorTexturePath.c_str()] sRGB:YES];
        }
        if (!importedMat.normalTexturePath.empty()) {
            mat.normalTexture = [texCache textureAtPath:
                [NSString stringWithUTF8String:importedMat.normalTexturePath.c_str()] sRGB:NO];
        }
        if (!importedMat.specularTexturePath.empty()) {
            mat.specularTexture = [texCache textureAtPath:
                [NSString stringWithUTF8String:importedMat.specularTexturePath.c_str()] sRGB:NO];
        }
        if (!importedMat.emissiveTexturePath.empty()) {
            mat.emissiveTexture = [texCache textureAtPath:
                [NSString stringWithUTF8String:importedMat.emissiveTexturePath.c_str()] sRGB:YES];
        }

        // Copy scalar fallbacks
        mat.baseColorFactor = importedMat.baseColorFactor;
        mat.roughnessFactor = importedMat.roughnessFactor;
        mat.metallicFactor  = importedMat.metallicFactor;
        mat.emissiveFactor  = importedMat.emissiveFactor;
        mat.opacity         = importedMat.opacity;

        [materials addObject:mat];
    }

    NSLog(@"SceneLoader: textures loaded — %lu loaded, %lu failed",
          (unsigned long)texCache.loadedCount, (unsigned long)texCache.failedCount);

    // Convert meshes (move data, no copies)
    std::vector<MeshAsset> meshes;
    meshes.reserve(imported->meshes.size());
    for (auto &importedMesh : imported->meshes) {
        MeshAsset mesh;
        mesh.name = std::move(importedMesh.name);
        mesh.indices = std::move(importedMesh.indices);
        mesh.positions = std::move(importedMesh.positions);
        mesh.normals = std::move(importedMesh.normals);
        mesh.uvs = std::move(importedMesh.uvs);
        mesh.tangents = std::move(importedMesh.tangents);
        mesh.materialIndex = importedMesh.materialIndex;
        meshes.push_back(std::move(mesh));
    }

    // Convert instances
    std::vector<SceneInstance> instances;
    instances.reserve(imported->instances.size());
    for (const auto &importedInst : imported->instances) {
        SceneInstance inst;
        inst.meshIndex = importedInst.meshIndex;
        inst.worldTransform = importedInst.worldTransform;
        instances.push_back(inst);
    }

    // Create SceneAsset
    SceneAsset *sceneAsset = [[SceneAsset alloc] initWithMeshes:std::move(meshes)
                                                      materials:materials
                                                      instances:std::move(instances)
                                                   textureCache:texCache];

    sceneAsset.boundsMin = imported->boundsMin;
    sceneAsset.boundsMax = imported->boundsMax;

    sceneAsset.cameraPosition = simd_make_float3(-12.34f, 5.94f, 1.67f);
    sceneAsset.cameraTarget = simd_make_float3(-11.48f, 5.50f, 1.41f);

    NSLog(@"SceneLoader: scene ready — %zu meshes, %zu materials, %zu instances, camera at (%.1f, %.1f, %.1f)",
          sceneAsset.meshes.size(), sceneAsset.materials.count, sceneAsset.instances.size(),
          sceneAsset.cameraPosition.x, sceneAsset.cameraPosition.y, sceneAsset.cameraPosition.z);

    delete imported;
    return sceneAsset;
}

+ (SceneAsset *)loadSceneFromFBX:(NSString *)fbxPath
                          device:(id<MTLDevice>)device
                           error:(NSError **)error {
    NSLog(@"SceneLoader: importing %@...", fbxPath.lastPathComponent);
    ImportedScene *imported = [SceneImporter importFBXAtPath:fbxPath error:error];
    if (!imported) return nil;

    return [self _buildSceneAssetFromImported:imported device:device];
}

+ (SceneAsset *)loadSceneFromFBXPaths:(NSArray<NSString *> *)fbxPaths
                               device:(id<MTLDevice>)device
                                error:(NSError **)error {
    if (fbxPaths.count == 0) {
        if (error) *error = [NSError errorWithDomain:@"SceneLoader" code:2
                            userInfo:@{NSLocalizedDescriptionKey: @"No FBX paths provided"}];
        return nil;
    }

    if (fbxPaths.count == 1) {
        return [self loadSceneFromFBX:fbxPaths[0] device:device error:error];
    }

    NSLog(@"SceneLoader: loading %lu FBX files for merging...", (unsigned long)fbxPaths.count);

    ImportedScene *merged = nullptr;
    for (NSString *path in fbxPaths) {
        NSLog(@"SceneLoader: importing %@...", path.lastPathComponent);
        ImportedScene *scene = [SceneImporter importFBXAtPath:path error:error];
        if (!scene) {
            delete merged;
            return nil;
        }

        if (!merged) {
            merged = scene;
        } else {
            ImportedScene *combined = mergeImportedScenes(*merged, *scene);
            delete merged;
            delete scene;
            merged = combined;
        }
    }

    NSLog(@"SceneLoader: merged scene — %zu meshes, %zu materials, %zu instances, %llu triangles",
          merged->meshes.size(), merged->materials.size(),
          merged->instances.size(), merged->totalTriangles);

    return [self _buildSceneAssetFromImported:merged device:device];
}

@end
