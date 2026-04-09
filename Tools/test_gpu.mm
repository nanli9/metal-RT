#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import "SceneLoader.h"
#import "SceneAsset.h"
#import "GPUScene.h"
#import "SceneUploader.h"
#import "AccelerationStructureBuilder.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device) { NSLog(@"No Metal device"); return 1; }
        NSLog(@"Metal device: %@", device.name);

        id<MTLCommandQueue> queue = [device newCommandQueue];

        NSString *fbxPath = @"/Users/nan/Desktop/AcceleratingRayTracingUsingMetal/Bistro_v5_2/BistroExterior.fbx";
        if (argc > 1) fbxPath = [NSString stringWithUTF8String:argv[1]];

        NSError *error = nil;
        SceneAsset *scene = [SceneLoader loadSceneFromFBX:fbxPath device:device error:&error];
        if (!scene) { NSLog(@"FAILED: %@", error.localizedDescription); return 1; }

        GPUScene *gpuScene = [[GPUScene alloc] init];

        NSLog(@"\n=== GPU Upload ===");
        CFAbsoluteTime uploadStart = CFAbsoluteTimeGetCurrent();
        [SceneUploader uploadScene:scene toGPUScene:gpuScene device:device];
        NSLog(@"Upload: %.2fs", CFAbsoluteTimeGetCurrent() - uploadStart);

        NSLog(@"\n=== Acceleration Structure Build ===");
        [AccelerationStructureBuilder buildAccelerationStructuresForGPUScene:gpuScene
                                                                 sceneAsset:scene
                                                                     device:device
                                                                      queue:queue];

        NSLog(@"\n=== GPU Scene Summary ===");
        NSLog(@"Mesh count: %lu", (unsigned long)gpuScene.meshCount);
        NSLog(@"Instance count: %lu", (unsigned long)gpuScene.instanceCount);
        NSLog(@"Material count: %lu", (unsigned long)gpuScene.materialCount);
        NSLog(@"Texture count: %lu", (unsigned long)gpuScene.textures.count);
        NSLog(@"BLAS count: %lu", (unsigned long)gpuScene.primitiveAccelerationStructures.count);
        NSLog(@"TLAS: %@", gpuScene.instanceAccelerationStructure ? @"YES" : @"NO");
        NSLog(@"Done.");
    }
    return 0;
}
