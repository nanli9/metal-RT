/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The header for the renderer class that performs Metal setup and per-frame rendering.
*/

#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>

#import "Scene.h"

@class GPUScene;
@class SceneAsset;
struct RenderOptions;

@interface Renderer : NSObject <MTKViewDelegate>

- (instancetype)initWithDevice:(id<MTLDevice>)device
                         scene:(Scene *)scene;

- (instancetype)initWithDevice:(id<MTLDevice>)device
                      gpuScene:(GPUScene *)gpuScene
                    sceneAsset:(SceneAsset *)sceneAsset;

@property (nonatomic) simd_float3 cameraPosition;
@property (nonatomic) simd_float3 cameraTarget;

/// Reset frame accumulation (call when camera moves)
- (void)resetAccumulation;

/// The command queue used by the renderer (for ImGui to encode after RT passes)
@property (nonatomic, readonly) id<MTLCommandQueue> commandQueue;

@end
