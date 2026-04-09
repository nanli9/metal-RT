#pragma once

#import <Foundation/Foundation.h>
#include <simd/simd.h>
#include <vector>
#include "MeshAsset.h"

@class MaterialAsset;
@class TextureCache;

/// A placed instance of a mesh in the scene.
struct SceneInstance {
    uint32_t meshIndex;
    simd_float4x4 worldTransform;
};

/// Top-level engine scene container. Owns all mesh, material, and instance data.
/// Format-agnostic — no dependency on import layer.
@interface SceneAsset : NSObject

@property (nonatomic, readonly) std::vector<MeshAsset> &meshes;
@property (nonatomic, readonly) NSArray<MaterialAsset *> *materials;
@property (nonatomic, readonly) std::vector<SceneInstance> &instances;
@property (nonatomic, readonly) TextureCache *textureCache;

// Scene bounds
@property (nonatomic) simd_float3 boundsMin;
@property (nonatomic) simd_float3 boundsMax;

// Default camera
@property (nonatomic) simd_float3 cameraPosition;
@property (nonatomic) simd_float3 cameraTarget;

- (instancetype)initWithMeshes:(std::vector<MeshAsset>)meshes
                     materials:(NSArray<MaterialAsset *> *)materials
                     instances:(std::vector<SceneInstance>)instances
                  textureCache:(TextureCache *)textureCache;

@end
