/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
The implementation of the cross-platform view controller.
*/
#import "ViewController.h"
#import "Renderer.h"
#import "SceneLoader.h"
#import "SceneAsset.h"
#import "GPUScene.h"
#import "SceneUploader.h"
#import "AccelerationStructureBuilder.h"
#import "CameraController.h"
#import "ImGuiRenderer.h"
#include "imgui.h"

@implementation ViewController
{
    MTKView *_view;
    Renderer *_renderer;
    CameraController *_cameraController;
    ImGuiRenderer *_imguiRenderer;
    NSDate *_lastFrameTime;
    float _fps;
    int _fpsFrameCount;
    NSDate *_fpsLastTime;
}

/// Parse command-line arguments to determine which scene to load.
/// Returns nil for Cornell box, or an FBX path string.
- (NSString *)scenePathFromArguments
{
    NSArray<NSString *> *args = [NSProcessInfo processInfo].arguments;

    for (NSUInteger i = 1; i < args.count; i++) {
        NSString *arg = args[i];
        if ([arg hasPrefix:@"-"]) continue;

        if ([arg caseInsensitiveCompare:@"cornell-box"] == NSOrderedSame)
            return nil;

        return arg;
    }

    return nil;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    _view = (MTKView *)self.view;

#if TARGET_OS_IPHONE
    _view.device = MTLCreateSystemDefaultDevice();
#else
    NSArray<id<MTLDevice>> *devices = MTLCopyAllDevices();
    id<MTLDevice> selectedDevice;
    for (id<MTLDevice> device in devices) {
        if (device.supportsRaytracing) {
            if (!selectedDevice || !device.isLowPower)
                selectedDevice = device;
        }
    }
    _view.device = selectedDevice;
    NSLog(@"Selected Device: %@", _view.device.name);
#endif

    NSAssert(_view.device && _view.device.supportsRaytracing,
             @"Ray tracing isn't supported on this device");

#if TARGET_OS_IPHONE
    _view.backgroundColor = UIColor.blackColor;
#endif
    _view.colorPixelFormat = MTLPixelFormatRGBA16Float;

    NSString *fbxPath = [self scenePathFromArguments];

    if (fbxPath) {
        if (![fbxPath hasPrefix:@"/"])  {
            NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
            fbxPath = [[cwd stringByAppendingPathComponent:fbxPath] stringByStandardizingPath];
        }

        if ([[NSFileManager defaultManager] fileExistsAtPath:fbxPath]) {
            NSLog(@"Loading scene from %@", fbxPath);
            NSError *error = nil;
            SceneAsset *sceneAsset = [SceneLoader loadSceneFromFBX:fbxPath
                                                            device:_view.device
                                                             error:&error];
            if (sceneAsset) {
                GPUScene *gpuScene = [[GPUScene alloc] init];
                [SceneUploader uploadScene:sceneAsset toGPUScene:gpuScene device:_view.device];

                id<MTLCommandQueue> queue = [_view.device newCommandQueue];
                [AccelerationStructureBuilder buildAccelerationStructuresForGPUScene:gpuScene
                                                                         sceneAsset:sceneAsset
                                                                             device:_view.device
                                                                              queue:queue];

                _renderer = [[Renderer alloc] initWithDevice:_view.device
                                                    gpuScene:gpuScene
                                                  sceneAsset:sceneAsset];

                // Create camera controller from scene default camera
                _cameraController = [[CameraController alloc]
                    initWithPosition:sceneAsset.cameraPosition
                              target:sceneAsset.cameraTarget];
            } else {
                NSLog(@"Failed to load scene: %@. Falling back to Cornell box.", error.localizedDescription);
            }
        } else {
            NSLog(@"FBX file not found: %@. Falling back to Cornell box.", fbxPath);
        }
    }

    if (!_renderer) {
        NSLog(@"Using Cornell box scene");
        Scene *scene = [Scene newInstancedCornellBoxSceneWithDevice:_view.device
                                            useIntersectionFunctions:YES];
        _renderer = [[Renderer alloc] initWithDevice:_view.device scene:scene];
    }

    [_renderer mtkView:_view drawableSizeWillChange:_view.bounds.size];
    _view.delegate = self;
    _lastFrameTime = [NSDate date];
    _fpsLastTime = [NSDate date];
    _fps = 0;
    _fpsFrameCount = 0;

    // Initialize ImGui overlay
    _imguiRenderer = [[ImGuiRenderer alloc] initWithDevice:_view.device view:_view];
}

#pragma mark - MTKViewDelegate forwarding + camera update

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    [_renderer mtkView:view drawableSizeWillChange:size];
}

- (void)drawInMTKView:(MTKView *)view {
    if (_cameraController) {
        NSDate *now = [NSDate date];
        float dt = (float)[now timeIntervalSinceDate:_lastFrameTime];
        _lastFrameTime = now;
        dt = fminf(dt, 0.1f); // cap to avoid huge jumps

        [_cameraController updateWithDeltaTime:dt];

        // Push camera to renderer
        _renderer.cameraPosition = _cameraController.position;
        _renderer.cameraTarget = [_cameraController target];

        if ([_cameraController consumeDidMove])
            [_renderer resetAccumulation];
    }

    [_renderer drawInMTKView:view];

    // ImGui overlay — render FPS after RT passes
    if (_imguiRenderer && view.currentDrawable) {
        // Update FPS counter
        _fpsFrameCount++;
        NSTimeInterval elapsed = -[_fpsLastTime timeIntervalSinceNow];
        if (elapsed >= 0.5) {
            _fps = (float)_fpsFrameCount / (float)elapsed;
            _fpsFrameCount = 0;
            _fpsLastTime = [NSDate date];
        }

        [_imguiRenderer newFrame:view];

        ImGui::SetNextWindowPos(ImVec2(10, 10), ImGuiCond_FirstUseEver);
        ImGui::SetNextWindowSize(ImVec2(260, 80), ImGuiCond_FirstUseEver);
        ImGui::Begin("Render Settings");
        ImGui::Text("FPS: %.1f (%.2f ms)", _fps, _fps > 0 ? 1000.0f / _fps : 0.0f);

        RenderOptions opts = _renderer.renderOptions;
        bool rtChanged = false;

        if (ImGui::Checkbox("PBR Shading", &opts.enablePBR)) rtChanged = true;
        if (ImGui::Checkbox("Shadows", &opts.enableShadows)) rtChanged = true;
        if (ImGui::Checkbox("Reflections", &opts.enableReflections)) rtChanged = true;
        ImGui::Checkbox("Accumulation", &opts.enableAccumulation);

        if (ImGui::SliderInt("Bounces", &opts.maxBounces, 1, 5)) rtChanged = true;
        if (ImGui::SliderFloat("Emissive", &opts.emissiveIntensity, 0.0f, 20.0f, "%.1f")) rtChanged = true;
        ImGui::SliderFloat("Exposure", &opts.exposureAdjust, -4.0f, 4.0f, "%.1f EV");

        const char *debugItems[] = {
            "Off", "Primitive ID", "Material ID", "Barycentrics",
            "Base Color", "Normals", "NdotL", "Shadow", "Instance ID",
            "Lambert", "UV coords", "BaseTex@UV", "AO value", "BaseTexIdx",
            "GBuf Depth", "GBuf Normal", "GBuf Albedo", "Denoise Weight",
            "Motion Vectors", "SVGF Variance"
        };
        if (ImGui::Combo("Debug View", &opts.debugMode, debugItems, 20)) rtChanged = true;

        const char *denoiserItems[] = { "Off", "A-Trous", "SVGF" };
        int denoiserIdx = static_cast<int>(opts.denoiserMode);
        if (ImGui::Combo("Denoiser", &denoiserIdx, denoiserItems, 3)) {
            opts.denoiserMode = static_cast<DenoiserMode>(denoiserIdx);
            rtChanged = true;
        }
        if (opts.denoiserMode != DenoiserMode::Off) {
            ImGui::SliderInt("Denoise Iterations", &opts.atrousIterations, 1, 5);
            ImGui::SliderFloat("Sigma Color", &opts.denoiseSigmaColor, 0.1f, 10.0f, "%.2f");
            ImGui::SliderFloat("Sigma Normal", &opts.denoiseSigmaNormal, 1.0f, 256.0f, "%.0f");
            ImGui::SliderFloat("Sigma Depth", &opts.denoiseSigmaDepth, 0.1f, 10.0f, "%.2f");
        }

        ImGui::Separator();
        ImGui::Text("Upscaling");
        bool metalFXChanged = false;
        if (_renderer.metalFXSupported) {
            if (ImGui::Checkbox("MetalFX Upscaling", &opts.enableMetalFXUpscaling))
                metalFXChanged = true;
            if (opts.enableMetalFXUpscaling) {
                if (ImGui::SliderFloat("Render Scale", &opts.upscaleRatio, 0.25f, 1.0f, "%.2f"))
                    metalFXChanged = true;
                int iw = (int)(_view.drawableSize.width * opts.upscaleRatio);
                int ih = (int)(_view.drawableSize.height * opts.upscaleRatio);
                ImGui::Text("Internal: %dx%d  Display: %dx%d",
                           iw, ih,
                           (int)_view.drawableSize.width, (int)_view.drawableSize.height);
            }
        } else {
            ImGui::BeginDisabled(true);
            bool disabled = false;
            ImGui::Checkbox("MetalFX (not supported)", &disabled);
            ImGui::EndDisabled();
        }

        _renderer.renderOptions = opts;
        if (metalFXChanged) {
            [_renderer mtkView:_view drawableSizeWillChange:_view.drawableSize];
            rtChanged = true;
        }
        if (rtChanged)
            [_renderer resetAccumulation];

        if (_cameraController) {
            ImGui::Separator();
            ImGui::Text("Camera");
            simd_float3 pos = _cameraController.position;
            simd_float3 tgt = [_cameraController target];
            float yawDeg = _cameraController.yaw * (180.0f / M_PI);
            float pitchDeg = _cameraController.pitch * (180.0f / M_PI);
            ImGui::Text("Pos:   (%.2f, %.2f, %.2f)", pos.x, pos.y, pos.z);
            ImGui::Text("Target:(%.2f, %.2f, %.2f)", tgt.x, tgt.y, tgt.z);
            ImGui::Text("Yaw: %.1f  Pitch: %.1f", yawDeg, pitchDeg);
            ImGui::Text("Speed: %.1f", _cameraController.moveSpeed);
        }
        ImGui::End();

        id<MTLCommandBuffer> cmdBuf = [_renderer.commandQueue commandBuffer];
        [_imguiRenderer renderWithCommandBuffer:cmdBuf drawable:view.currentDrawable];
        [cmdBuf commit];
    }
}

#pragma mark - macOS input events

#if !TARGET_OS_IPHONE

- (BOOL)acceptsFirstResponder { return YES; }

// Need to accept first mouse so clicks in window work even if not focused
- (BOOL)becomeFirstResponder { return YES; }

- (void)viewDidAppear {
    [super viewDidAppear];
    [self.view.window makeFirstResponder:self];
}

- (void)keyDown:(NSEvent *)event {
    if (_cameraController)
        [_cameraController keyDown:event.keyCode];
}

- (void)keyUp:(NSEvent *)event {
    if (_cameraController)
        [_cameraController keyUp:event.keyCode];
}

- (void)mouseDragged:(NSEvent *)event {
    if (_cameraController)
        [_cameraController mouseMovedDeltaX:(float)event.deltaX deltaY:(float)event.deltaY];
}

- (void)rightMouseDragged:(NSEvent *)event {
    if (_cameraController)
        [_cameraController mouseMovedDeltaX:(float)event.deltaX deltaY:(float)event.deltaY];
}

- (void)scrollWheel:(NSEvent *)event {
    if (_cameraController)
        [_cameraController scrollWheelDeltaY:(float)event.deltaY];
}

#endif

@end
