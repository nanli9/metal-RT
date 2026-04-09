#import "AccelerationStructureBuilder.h"
#import "GPUScene+Private.h"
#import "SceneAsset.h"
#import "MeshAsset.h"
#import "ShaderTypes.h"

@implementation AccelerationStructureBuilder

/// Build and compact a single acceleration structure.
+ (id<MTLAccelerationStructure>)buildAccelWithDescriptor:(MTLAccelerationStructureDescriptor *)descriptor
                                                  device:(id<MTLDevice>)device
                                                   queue:(id<MTLCommandQueue>)queue
{
    MTLAccelerationStructureSizes sizes = [device accelerationStructureSizesWithDescriptor:descriptor];

    id<MTLAccelerationStructure> accel = [device newAccelerationStructureWithSize:sizes.accelerationStructureSize];
    id<MTLBuffer> scratch = [device newBufferWithLength:sizes.buildScratchBufferSize options:MTLResourceStorageModePrivate];
    id<MTLBuffer> compactedSizeBuf = [device newBufferWithLength:sizeof(uint32_t) options:MTLResourceStorageModeShared];

    id<MTLCommandBuffer> cmdBuf = [queue commandBuffer];
    id<MTLAccelerationStructureCommandEncoder> encoder = [cmdBuf accelerationStructureCommandEncoder];

    [encoder buildAccelerationStructure:accel
                             descriptor:descriptor
                          scratchBuffer:scratch
                    scratchBufferOffset:0];

    [encoder writeCompactedAccelerationStructureSize:accel
                                            toBuffer:compactedSizeBuf
                                              offset:0];
    [encoder endEncoding];
    [cmdBuf commit];
    [cmdBuf waitUntilCompleted];

    uint32_t compactedSize = *(uint32_t *)compactedSizeBuf.contents;

    id<MTLAccelerationStructure> compacted = [device newAccelerationStructureWithSize:compactedSize];

    cmdBuf = [queue commandBuffer];
    encoder = [cmdBuf accelerationStructureCommandEncoder];
    [encoder copyAndCompactAccelerationStructure:accel toAccelerationStructure:compacted];
    [encoder endEncoding];
    [cmdBuf commit];
    [cmdBuf waitUntilCompleted];

    return compacted;
}

+ (void)buildAccelerationStructuresForGPUScene:(GPUScene *)gpuScene
                                    sceneAsset:(SceneAsset *)sceneAsset
                                        device:(id<MTLDevice>)device
                                         queue:(id<MTLCommandQueue>)queue
{
    auto &meshInfos = gpuScene.meshInfos;
    auto &instances = sceneAsset.instances;

    NSLog(@"AccelerationStructureBuilder: building %zu BLAS...", meshInfos.size());
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();

    // ---- Build one BLAS per mesh ----
    NSMutableArray<id<MTLAccelerationStructure>> *blasArray = [NSMutableArray new];

    for (size_t mi = 0; mi < meshInfos.size(); mi++) {
        auto &info = meshInfos[mi];

        MTLAccelerationStructureTriangleGeometryDescriptor *geomDesc =
            [MTLAccelerationStructureTriangleGeometryDescriptor descriptor];

        geomDesc.vertexBuffer = gpuScene.vertexPositionBuffer;
        geomDesc.vertexBufferOffset = info.vertexOffset * sizeof(simd_float3);
        geomDesc.vertexStride = sizeof(simd_float3);
        geomDesc.vertexFormat = MTLAttributeFormatFloat3;

        geomDesc.indexBuffer = gpuScene.indexBuffer;
        geomDesc.indexBufferOffset = info.indexOffset * sizeof(uint32_t);
        geomDesc.indexType = MTLIndexTypeUInt32;

        geomDesc.triangleCount = info.indexCount / 3;

        // Per-primitive data for this mesh's triangles
        geomDesc.primitiveDataBuffer = gpuScene.perPrimitiveDataBuffer;
        geomDesc.primitiveDataBufferOffset = info.triangleOffset * sizeof(GPUTriangleData);
        geomDesc.primitiveDataStride = sizeof(GPUTriangleData);
        geomDesc.primitiveDataElementSize = sizeof(GPUTriangleData);

        // All Bistro geometry is opaque triangles (no intersection functions)
        geomDesc.opaque = YES;

        MTLPrimitiveAccelerationStructureDescriptor *accelDesc = [MTLPrimitiveAccelerationStructureDescriptor descriptor];
        accelDesc.geometryDescriptors = @[ geomDesc ];

        id<MTLAccelerationStructure> blas = [self buildAccelWithDescriptor:accelDesc device:device queue:queue];
        [blasArray addObject:blas];
    }

    CFAbsoluteTime blasTime = CFAbsoluteTimeGetCurrent() - start;
    NSLog(@"AccelerationStructureBuilder: %zu BLAS built in %.2fs", blasArray.count, blasTime);

    // ---- Fill instance descriptors and build TLAS ----
    MTLAccelerationStructureInstanceDescriptor *instDescs =
        (MTLAccelerationStructureInstanceDescriptor *)gpuScene.instanceBuffer.contents;

    for (size_t i = 0; i < instances.size(); i++) {
        auto &inst = instances[i];

        instDescs[i].accelerationStructureIndex = inst.meshIndex;
        instDescs[i].options = MTLAccelerationStructureInstanceOptionOpaque;
        instDescs[i].intersectionFunctionTableOffset = 0;
        instDescs[i].mask = GEOMETRY_MASK_TRIANGLE;

        // Copy 4x3 transform (Metal assumes bottom row is [0,0,0,1])
        for (int col = 0; col < 4; col++)
            for (int row = 0; row < 3; row++)
                instDescs[i].transformationMatrix.columns[col][row] = inst.worldTransform.columns[col][row];
    }

    MTLInstanceAccelerationStructureDescriptor *tlasDesc = [MTLInstanceAccelerationStructureDescriptor descriptor];
    tlasDesc.instancedAccelerationStructures = blasArray;
    tlasDesc.instanceCount = instances.size();
    tlasDesc.instanceDescriptorBuffer = gpuScene.instanceBuffer;

    NSLog(@"AccelerationStructureBuilder: building TLAS with %zu instances...", instances.size());
    CFAbsoluteTime tlasStart = CFAbsoluteTimeGetCurrent();

    id<MTLAccelerationStructure> tlas = [self buildAccelWithDescriptor:tlasDesc device:device queue:queue];

    NSLog(@"AccelerationStructureBuilder: TLAS built in %.2fs", CFAbsoluteTimeGetCurrent() - tlasStart);

    // ---- Store on GPUScene ----
    [gpuScene setPrimitiveAccelerationStructures:blasArray];
    [gpuScene setInstanceAccelerationStructure:tlas];

    NSLog(@"AccelerationStructureBuilder: total build time %.2fs", CFAbsoluteTimeGetCurrent() - start);
}

@end
