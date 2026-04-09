#pragma once

#import <Metal/Metal.h>
#import <Foundation/Foundation.h>

@class GPUScene;
@class SceneAsset;

/// Builds BLAS (one per unique mesh) and TLAS (instance acceleration structure)
/// from the GPU buffers on a GPUScene. Supports compaction.
@interface AccelerationStructureBuilder : NSObject

+ (void)buildAccelerationStructuresForGPUScene:(GPUScene *)gpuScene
                                    sceneAsset:(SceneAsset *)sceneAsset
                                        device:(id<MTLDevice>)device
                                         queue:(id<MTLCommandQueue>)queue;

@end
