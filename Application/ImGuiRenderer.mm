#import "ImGuiRenderer.h"

#include "imgui.h"
#include "imgui_impl_metal.h"
#include "imgui_impl_osx.h"

@implementation ImGuiRenderer {
    id<MTLDevice> _device;
    MTLRenderPassDescriptor *_renderPassDesc;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device
                          view:(MTKView *)view {
    self = [super init];
    if (self) {
        _device = device;

        IMGUI_CHECKVERSION();
        ImGui::CreateContext();

        ImGuiIO &io = ImGui::GetIO();
        io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;
        ImGui::StyleColorsDark();

        // Make UI slightly transparent so RT image shows through
        ImGuiStyle &style = ImGui::GetStyle();
        style.Alpha = 0.9f;

        ImGui_ImplMetal_Init(device);
        ImGui_ImplOSX_Init(view);

        _renderPassDesc = [MTLRenderPassDescriptor new];
        _renderPassDesc.colorAttachments[0].loadAction = MTLLoadActionLoad;
        _renderPassDesc.colorAttachments[0].storeAction = MTLStoreActionStore;
        _renderPassDesc.rasterizationRateMap = nil;
    }
    return self;
}

- (void)dealloc {
    ImGui_ImplMetal_Shutdown();
    ImGui_ImplOSX_Shutdown();
    ImGui::DestroyContext();
}

- (void)newFrame:(MTKView *)view {
    // Set the drawable texture so ImGui can read sampleCount for pipeline creation
    _renderPassDesc.colorAttachments[0].texture = view.currentDrawable.texture;
    ImGui_ImplMetal_NewFrame(_renderPassDesc);
    ImGui_ImplOSX_NewFrame(view);
    ImGui::NewFrame();
}

- (void)renderWithCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                       drawable:(id<CAMetalDrawable>)drawable {
    ImGui::Render();

    _renderPassDesc.colorAttachments[0].texture = drawable.texture;

    id<MTLRenderCommandEncoder> encoder =
        [commandBuffer renderCommandEncoderWithDescriptor:_renderPassDesc];
    encoder.label = @"ImGui Render";

    ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), commandBuffer, encoder);

    [encoder endEncoding];
}

// Note: newer Dear ImGui OSX backend handles events via the responder chain automatically

@end
