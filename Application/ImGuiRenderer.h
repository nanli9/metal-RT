#pragma once

#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>

#if !TARGET_OS_IPHONE
#import <Cocoa/Cocoa.h>
#endif

/// Wraps Dear ImGui initialization, per-frame update, and Metal rendering.
/// Renders in its own render pass (loadAction:Load) composited over the RT output.
@interface ImGuiRenderer : NSObject

- (instancetype)initWithDevice:(id<MTLDevice>)device
                          view:(MTKView *)view;

/// Call at the start of each frame before building UI.
- (void)newFrame:(MTKView *)view;

/// Call after building UI. Encodes ImGui draw commands into the command buffer.
- (void)renderWithCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                       drawable:(id<CAMetalDrawable>)drawable;

@end
