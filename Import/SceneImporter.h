#pragma once

#import <Foundation/Foundation.h>
#include "ImportedScene.h"

/// Imports FBX scenes using ufbx and converts them into engine-independent
/// ImportedScene structures. This is the ONLY file that depends on ufbx.
@interface SceneImporter : NSObject

/// Load an FBX file and return the imported scene data.
/// @param path Absolute path to the .fbx file
/// @param error Set on failure
/// @return ImportedScene pointer (caller takes ownership via delete), or nullptr on failure
+ (ImportedScene * _Nullable)importFBXAtPath:(NSString * _Nonnull)path
                                       error:(NSError * _Nullable * _Nullable)error;

@end
