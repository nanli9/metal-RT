#pragma once

#import <Metal/Metal.h>
#import <Foundation/Foundation.h>

@class SceneAsset;

/// Loads FBX file(s) and produces a fully resolved SceneAsset with textures loaded.
/// This is the bridge between the Import layer and the Runtime Scene layer.
@interface SceneLoader : NSObject

+ (SceneAsset *)loadSceneFromFBX:(NSString *)fbxPath
                          device:(id<MTLDevice>)device
                           error:(NSError **)error;

/// Load multiple FBX files and merge them into a single SceneAsset.
/// Files are imported in order and merged with proper index remapping.
+ (SceneAsset *)loadSceneFromFBXPaths:(NSArray<NSString *> *)fbxPaths
                               device:(id<MTLDevice>)device
                                error:(NSError **)error;

@end
