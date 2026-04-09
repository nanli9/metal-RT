#pragma once

#import <Metal/Metal.h>
#import <Foundation/Foundation.h>
#include <simd/simd.h>
#include <vector>

@class SceneAsset;

/// Per-mesh metadata: vertex/index offsets for BLAS building and GPU buffer layout.
struct MeshGPUInfo {
    uint32_t vertexOffset;
    uint32_t vertexCount;
    uint32_t indexOffset;
    uint32_t indexCount;
    uint32_t triangleOffset;  // offset into perPrimitiveDataBuffer
    uint32_t materialIndex;
};

/// GPU-resident scene data. Owns all Metal buffers, textures, and acceleration structures
/// needed for ray tracing the scene. Consumes SceneAsset (runtime layer), not raw FBX data.
@interface GPUScene : NSObject

// Geometry buffers (one contiguous buffer each, all meshes packed sequentially)
@property (nonatomic, readonly) id<MTLBuffer> vertexPositionBuffer;
@property (nonatomic, readonly) id<MTLBuffer> vertexNormalBuffer;
@property (nonatomic, readonly) id<MTLBuffer> vertexUVBuffer;
@property (nonatomic, readonly) id<MTLBuffer> vertexTangentBuffer;
@property (nonatomic, readonly) id<MTLBuffer> indexBuffer;

// Per-mesh offset info for building BLAS
@property (nonatomic, readonly) NSUInteger meshCount;

// Per-primitive data: one GPUTriangleData per triangle
@property (nonatomic, readonly) id<MTLBuffer> perPrimitiveDataBuffer;

// Material buffer: array of GPUMaterial structs
@property (nonatomic, readonly) id<MTLBuffer> materialBuffer;
@property (nonatomic, readonly) NSUInteger materialCount;

// Scene textures (all loaded textures, indexed by materialTextureIndex)
@property (nonatomic, readonly) NSArray<id<MTLTexture>> *textures;

// Instance data
@property (nonatomic, readonly) id<MTLBuffer> instanceBuffer;
@property (nonatomic, readonly) NSUInteger instanceCount;

// Acceleration structures
@property (nonatomic, readonly) NSArray<id<MTLAccelerationStructure>> *primitiveAccelerationStructures;
@property (nonatomic, readonly) id<MTLAccelerationStructure> instanceAccelerationStructure;

// Per-mesh metadata
@property (nonatomic, readonly) const std::vector<MeshGPUInfo> &meshInfos;

@end
