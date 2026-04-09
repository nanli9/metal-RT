#pragma once

#import "GPUScene.h"

/// Private setters used by SceneUploader and AccelerationStructureBuilder.
@interface GPUScene (Private)

- (void)setVertexPositionBuffer:(id<MTLBuffer>)buf;
- (void)setVertexNormalBuffer:(id<MTLBuffer>)buf;
- (void)setVertexUVBuffer:(id<MTLBuffer>)buf;
- (void)setVertexTangentBuffer:(id<MTLBuffer>)buf;
- (void)setIndexBuffer:(id<MTLBuffer>)buf;
- (void)setPerPrimitiveDataBuffer:(id<MTLBuffer>)buf;
- (void)setMaterialBuffer:(id<MTLBuffer>)buf;
- (void)setMaterialCount:(NSUInteger)count;
- (void)setTextures:(NSArray<id<MTLTexture>> *)textures;
- (void)setTextureResourceIDBuffer:(id<MTLBuffer>)buf;
- (void)setInstanceBuffer:(id<MTLBuffer>)buf;
- (void)setInstanceCount:(NSUInteger)count;
- (void)setPrimitiveAccelerationStructures:(NSArray<id<MTLAccelerationStructure>> *)arr;
- (void)setInstanceAccelerationStructure:(id<MTLAccelerationStructure>)as;
- (void)setMeshInfos:(std::vector<MeshGPUInfo>)infos;

@end
