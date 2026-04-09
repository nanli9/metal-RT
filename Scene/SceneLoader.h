#pragma once

#import <Metal/Metal.h>
#import <Foundation/Foundation.h>

@class SceneAsset;

/// Loads an FBX file and produces a fully resolved SceneAsset with textures loaded.
/// This is the bridge between the Import layer and the Runtime Scene layer.
@interface SceneLoader : NSObject

+ (SceneAsset *)loadSceneFromFBX:(NSString *)fbxPath
                          device:(id<MTLDevice>)device
                           error:(NSError **)error;

@end
