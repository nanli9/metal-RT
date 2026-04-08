#import <Foundation/Foundation.h>
#import "SceneImporter.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *path = nil;

        if (argc > 1) {
            path = [NSString stringWithUTF8String:argv[1]];
        } else {
            // Default to BistroExterior.fbx relative to this tool's location
            NSString *repoRoot = [[[NSProcessInfo processInfo].arguments[0]
                                   stringByDeletingLastPathComponent]
                                   stringByAppendingPathComponent:@".."];
            repoRoot = [repoRoot stringByStandardizingPath];
            path = [repoRoot stringByAppendingPathComponent:@"Bistro_v5_2/BistroExterior.fbx"];
        }

        NSLog(@"Loading %@...", path);
        NSError *error = nil;
        CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();

        ImportedScene *scene = [SceneImporter importFBXAtPath:path error:&error];
        CFAbsoluteTime elapsed = CFAbsoluteTimeGetCurrent() - start;

        if (!scene) {
            NSLog(@"FAILED: %@", error.localizedDescription);
            return 1;
        }

        NSLog(@"=== Import Summary (%.2fs) ===", elapsed);
        NSLog(@"Meshes: %zu", scene->meshes.size());
        NSLog(@"Materials: %zu", scene->materials.size());
        NSLog(@"Instances: %zu", scene->instances.size());
        NSLog(@"Total triangles: %llu", scene->totalTriangles);
        NSLog(@"Total vertices: %llu", scene->totalVertices);
        NSLog(@"Bounds: (%.2f,%.2f,%.2f) to (%.2f,%.2f,%.2f)",
              scene->boundsMin.x, scene->boundsMin.y, scene->boundsMin.z,
              scene->boundsMax.x, scene->boundsMax.y, scene->boundsMax.z);

        NSLog(@"\n=== Materials (%zu) ===", scene->materials.size());
        for (size_t i = 0; i < scene->materials.size(); i++) {
            auto &m = scene->materials[i];
            NSLog(@"  [%zu] %s", i, m.name.c_str());
            if (!m.baseColorTexturePath.empty())
                NSLog(@"       baseColor: %s", m.baseColorTexturePath.c_str());
            if (!m.normalTexturePath.empty())
                NSLog(@"       normal: %s", m.normalTexturePath.c_str());
            if (!m.specularTexturePath.empty())
                NSLog(@"       specular: %s", m.specularTexturePath.c_str());
            if (!m.emissiveTexturePath.empty())
                NSLog(@"       emissive: %s", m.emissiveTexturePath.c_str());
        }

        NSLog(@"\n=== First 20 Meshes ===");
        for (size_t i = 0; i < std::min(scene->meshes.size(), (size_t)20); i++) {
            auto &m = scene->meshes[i];
            NSLog(@"  [%zu] '%s' — %zu tris, %zu verts, mat=%u",
                  i, m.name.c_str(), m.indices.size()/3, m.positions.size(), m.materialIndex);
        }

        // Count textures resolved vs missing
        size_t resolved = 0, missing = 0;
        for (auto &m : scene->materials) {
            auto check = [&](const std::string &p) { if (!p.empty()) resolved++; else missing++; };
            check(m.baseColorTexturePath);
            check(m.normalTexturePath);
            check(m.specularTexturePath);
            check(m.emissiveTexturePath);
        }
        NSLog(@"\n=== Texture Resolution ===");
        NSLog(@"Resolved: %zu, Missing: %zu", resolved, missing);

        delete scene;
        NSLog(@"Done.");
    }
    return 0;
}
