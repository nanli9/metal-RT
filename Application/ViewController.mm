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

@implementation ViewController
{
    MTKView *_view;

    Renderer *_renderer;
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

    for(id<MTLDevice> device in devices)
    {
        if(device.supportsRaytracing)
        {
            if(!selectedDevice || !device.isLowPower)
            {
                selectedDevice = device;
            }
        }
    }
    _view.device = selectedDevice;

    NSLog(@"Selected Device: %@", _view.device.name);
#endif

    // Device must support Metal and ray tracing.
    NSAssert(_view.device && _view.device.supportsRaytracing,
             @"Ray tracing isn't supported on this device");

#if TARGET_OS_IPHONE
    _view.backgroundColor = UIColor.blackColor;
#endif
    _view.colorPixelFormat = MTLPixelFormatRGBA16Float;

    // Try to load Bistro scene, fall back to Cornell box.
    // Search for Bistro_v5_2/ in several locations:
    // 1. Alongside the .xcodeproj (SOURCE_ROOT set by Xcode)
    // 2. Walking up from the executable (DerivedData runs)
    // 3. Hardcoded known project path
    NSString *bistroPath = nil;
    NSArray<NSString *> *searchRoots = @[
        // Xcode sets this environment variable to the project source root
        [[NSProcessInfo processInfo].environment[@"__XCODE_BUILT_PRODUCTS_DIR_PATHS"] stringByDeletingLastPathComponent] ?: @"",
        // Walk up from executable
        [[[NSProcessInfo processInfo].arguments[0] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"../.."],
        // Known project location
        @"/Users/nan/Desktop/AcceleratingRayTracingUsingMetal",
    ];

    for (NSString *root in searchRoots) {
        if (root.length == 0) continue;
        NSString *candidate = [[root stringByStandardizingPath]
                               stringByAppendingPathComponent:@"Bistro_v5_2/BistroExterior.fbx"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:candidate]) {
            bistroPath = candidate;
            break;
        }
    }

    if (bistroPath) {
        NSLog(@"Loading Bistro scene from %@", bistroPath);

        NSError *error = nil;
        SceneAsset *sceneAsset = [SceneLoader loadSceneFromFBX:bistroPath
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
        } else {
            NSLog(@"Failed to load Bistro: %@. Falling back to Cornell box.", error.localizedDescription);
        }
    }

    if (!_renderer) {
        // Fallback: Cornell box
        NSLog(@"Using Cornell box scene");
        Scene *scene = [Scene newInstancedCornellBoxSceneWithDevice:_view.device
                                            useIntersectionFunctions:YES];
        _renderer = [[Renderer alloc] initWithDevice:_view.device scene:scene];
    }

    [_renderer mtkView:_view drawableSizeWillChange:_view.bounds.size];

    _view.delegate = _renderer;
}

@end
