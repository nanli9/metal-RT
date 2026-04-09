#import "SceneLoader.h"
#import "SceneAsset.h"
#import "MaterialAsset.h"
#import "TextureAsset.h"
#import "TextureCache.h"
#import "MeshAsset.h"
#import "SceneImporter.h"
#import "ImportedScene.h"

@implementation SceneLoader

+ (SceneAsset *)loadSceneFromFBX:(NSString *)fbxPath
                          device:(id<MTLDevice>)device
                           error:(NSError **)error {
    // Step 1: Import FBX
    NSLog(@"SceneLoader: importing %@...", fbxPath.lastPathComponent);
    ImportedScene *imported = [SceneImporter importFBXAtPath:fbxPath error:error];
    if (!imported) return nil;

    // Step 2: Load textures
    NSLog(@"SceneLoader: loading textures...");
    TextureCache *texCache = [[TextureCache alloc] initWithDevice:device];

    // Step 3: Convert materials
    NSMutableArray<MaterialAsset *> *materials = [NSMutableArray new];
    for (const auto &importedMat : imported->materials) {
        MaterialAsset *mat = [[MaterialAsset alloc] init];
        mat.name = [NSString stringWithUTF8String:importedMat.name.c_str()];

        // Resolve textures via cache
        if (!importedMat.baseColorTexturePath.empty()) {
            mat.baseColorTexture = [texCache textureAtPath:
                [NSString stringWithUTF8String:importedMat.baseColorTexturePath.c_str()]];
        }
        if (!importedMat.normalTexturePath.empty()) {
            mat.normalTexture = [texCache textureAtPath:
                [NSString stringWithUTF8String:importedMat.normalTexturePath.c_str()]];
        }
        if (!importedMat.specularTexturePath.empty()) {
            mat.specularTexture = [texCache textureAtPath:
                [NSString stringWithUTF8String:importedMat.specularTexturePath.c_str()]];
        }
        if (!importedMat.emissiveTexturePath.empty()) {
            mat.emissiveTexture = [texCache textureAtPath:
                [NSString stringWithUTF8String:importedMat.emissiveTexturePath.c_str()]];
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

    // Step 4: Convert meshes (move data, no copies)
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

    // Step 5: Convert instances
    std::vector<SceneInstance> instances;
    instances.reserve(imported->instances.size());
    for (const auto &importedInst : imported->instances) {
        SceneInstance inst;
        inst.meshIndex = importedInst.meshIndex;
        inst.worldTransform = importedInst.worldTransform;
        instances.push_back(inst);
    }

    // Step 6: Create SceneAsset
    SceneAsset *sceneAsset = [[SceneAsset alloc] initWithMeshes:std::move(meshes)
                                                      materials:materials
                                                      instances:std::move(instances)
                                                   textureCache:texCache];

    sceneAsset.boundsMin = imported->boundsMin;
    sceneAsset.boundsMax = imported->boundsMax;

    sceneAsset.cameraPosition = simd_make_float3(-10.5f, 1.7f, -1.0f);
    sceneAsset.cameraTarget = simd_make_float3(0.0f, 3.5f, 0.0f);

    NSLog(@"SceneLoader: scene ready — %zu meshes, %zu materials, %zu instances, camera at (%.1f, %.1f, %.1f)",
          sceneAsset.meshes.size(), sceneAsset.materials.count, sceneAsset.instances.size(),
          sceneAsset.cameraPosition.x, sceneAsset.cameraPosition.y, sceneAsset.cameraPosition.z);

    delete imported;
    return sceneAsset;
}

@end
