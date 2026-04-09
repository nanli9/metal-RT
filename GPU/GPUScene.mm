#import "GPUScene.h"

@implementation GPUScene {
    std::vector<MeshGPUInfo> _meshInfos;
}

- (instancetype)init {
    self = [super init];
    return self;
}

- (const std::vector<MeshGPUInfo> &)meshInfos { return _meshInfos; }
- (NSUInteger)meshCount { return _meshInfos.size(); }

// These setters are used by SceneUploader and AccelerationStructureBuilder
- (void)setVertexPositionBuffer:(id<MTLBuffer>)buf { _vertexPositionBuffer = buf; }
- (void)setVertexNormalBuffer:(id<MTLBuffer>)buf { _vertexNormalBuffer = buf; }
- (void)setVertexUVBuffer:(id<MTLBuffer>)buf { _vertexUVBuffer = buf; }
- (void)setVertexTangentBuffer:(id<MTLBuffer>)buf { _vertexTangentBuffer = buf; }
- (void)setIndexBuffer:(id<MTLBuffer>)buf { _indexBuffer = buf; }
- (void)setPerPrimitiveDataBuffer:(id<MTLBuffer>)buf { _perPrimitiveDataBuffer = buf; }
- (void)setMaterialBuffer:(id<MTLBuffer>)buf { _materialBuffer = buf; }
- (void)setMaterialCount:(NSUInteger)count { _materialCount = count; }
- (void)setTextures:(NSArray<id<MTLTexture>> *)textures { _textures = textures; }
- (void)setTextureResourceIDBuffer:(id<MTLBuffer>)buf { _textureResourceIDBuffer = buf; }
- (void)setInstanceBuffer:(id<MTLBuffer>)buf { _instanceBuffer = buf; }
- (void)setInstanceCount:(NSUInteger)count { _instanceCount = count; }
- (void)setPrimitiveAccelerationStructures:(NSArray<id<MTLAccelerationStructure>> *)arr { _primitiveAccelerationStructures = arr; }
- (void)setInstanceAccelerationStructure:(id<MTLAccelerationStructure>)as { _instanceAccelerationStructure = as; }
- (void)setMeshInfos:(std::vector<MeshGPUInfo>)infos { _meshInfos = std::move(infos); }

@end
