#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import "SceneLoader.h"
#import "SceneAsset.h"
#import "MaterialAsset.h"
#import "TextureAsset.h"
#import "TextureCache.h"
#import "MeshAsset.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device) { NSLog(@"No Metal device"); return 1; }
        NSLog(@"Metal device: %@", device.name);

        NSString *fbxPath = @"/Users/nan/Desktop/AcceleratingRayTracingUsingMetal/Bistro_v5_2/BistroExterior.fbx";
        if (argc > 1) fbxPath = [NSString stringWithUTF8String:argv[1]];

        NSError *error = nil;
        CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
        SceneAsset *scene = [SceneLoader loadSceneFromFBX:fbxPath device:device error:&error];
        CFAbsoluteTime elapsed = CFAbsoluteTimeGetCurrent() - start;

        if (!scene) {
            NSLog(@"FAILED: %@", error.localizedDescription);
            return 1;
        }

        NSLog(@"\n=== SceneAsset Summary (%.2fs total) ===", elapsed);
        NSLog(@"Meshes: %zu", scene.meshes.size());
        NSLog(@"Materials: %zu", scene.materials.count);
        NSLog(@"Instances: %zu", scene.instances.size());
        NSLog(@"Bounds: (%.2f,%.2f,%.2f) to (%.2f,%.2f,%.2f)",
              scene.boundsMin.x, scene.boundsMin.y, scene.boundsMin.z,
              scene.boundsMax.x, scene.boundsMax.y, scene.boundsMax.z);
        NSLog(@"Camera: (%.1f, %.1f, %.1f) -> (%.1f, %.1f, %.1f)",
              scene.cameraPosition.x, scene.cameraPosition.y, scene.cameraPosition.z,
              scene.cameraTarget.x, scene.cameraTarget.y, scene.cameraTarget.z);

        // Texture stats
        NSLog(@"\n=== Texture Stats ===");
        NSLog(@"Loaded: %lu, Failed: %lu",
              (unsigned long)scene.textureCache.loadedCount,
              (unsigned long)scene.textureCache.failedCount);

        // Material detail
        NSLog(@"\n=== Materials ===");
        for (NSUInteger i = 0; i < scene.materials.count; i++) {
            MaterialAsset *m = scene.materials[i];
            NSLog(@"  [%lu] %@ — baseColor:%@ normal:%@ specular:%@ emissive:%@",
                  (unsigned long)i, m.name,
                  m.baseColorTexture ? @"YES" : @"no",
                  m.normalTexture ? @"YES" : @"no",
                  m.specularTexture ? @"YES" : @"no",
                  m.emissiveTexture ? @"YES" : @"no");
        }

        // Count total triangles
        uint64_t totalTris = 0;
        for (auto &mesh : scene.meshes) totalTris += mesh.triangleCount();
        NSLog(@"\nTotal triangles: %llu", totalTris);

        NSLog(@"Done.");
    }
    return 0;
}
