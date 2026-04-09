#pragma once

#import <Metal/Metal.h>
#import <Foundation/Foundation.h>

@class SceneAsset;
@class GPUScene;

/// Uploads CPU-side SceneAsset data into GPU buffers on a GPUScene.
/// Creates vertex/index/material/per-primitive buffers and collects textures.
@interface SceneUploader : NSObject

+ (void)uploadScene:(SceneAsset *)sceneAsset
         toGPUScene:(GPUScene *)gpuScene
             device:(id<MTLDevice>)device;

@end
