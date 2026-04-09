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

/// Parse command-line arguments to determine which scene to load.
/// Returns nil for Cornell box, or an FBX path string.
- (NSString *)scenePathFromArguments
{
    NSArray<NSString *> *args = [NSProcessInfo processInfo].arguments;

    // Skip argv[0] (executable path). Look for the first non-flag argument.
    for (NSUInteger i = 1; i < args.count; i++) {
        NSString *arg = args[i];
        if ([arg hasPrefix:@"-"]) continue; // skip flags like -NSDocumentRevisionsDebugMode

        // "cornell-box" (case-insensitive) means use Cornell box
        if ([arg caseInsensitiveCompare:@"cornell-box"] == NSOrderedSame)
            return nil;

        // Anything else is treated as an FBX path
        return arg;
    }

    // No scene argument — default to Cornell box
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

    NSString *fbxPath = [self scenePathFromArguments];

    if (fbxPath) {
        // Resolve relative paths
        if (![fbxPath hasPrefix:@"/"]) {
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

    _view.delegate = _renderer;
}

@end
