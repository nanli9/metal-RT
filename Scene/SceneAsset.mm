#import "SceneAsset.h"
#import "MaterialAsset.h"
#import "TextureCache.h"

@implementation SceneAsset {
    std::vector<MeshAsset> _meshes;
    std::vector<SceneInstance> _instances;
}

- (instancetype)initWithMeshes:(std::vector<MeshAsset>)meshes
                     materials:(NSArray<MaterialAsset *> *)materials
                     instances:(std::vector<SceneInstance>)instances
                  textureCache:(TextureCache *)textureCache {
    self = [super init];
    if (self) {
        _meshes = std::move(meshes);
        _materials = materials;
        _instances = std::move(instances);
        _textureCache = textureCache;
        _boundsMin = simd_make_float3(0, 0, 0);
        _boundsMax = simd_make_float3(0, 0, 0);
        _cameraPosition = simd_make_float3(0, 1, 5);
        _cameraTarget = simd_make_float3(0, 1, 0);
    }
    return self;
}

- (std::vector<MeshAsset> &)meshes { return _meshes; }
- (std::vector<SceneInstance> &)instances { return _instances; }

@end
