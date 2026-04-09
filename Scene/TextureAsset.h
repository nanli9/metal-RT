#pragma once

#import <Metal/Metal.h>
#import <Foundation/Foundation.h>
#include <string>

/// Engine-owned texture wrapper. Holds a loaded MTLTexture and its source path.
@interface TextureAsset : NSObject

@property (nonatomic, readonly) id<MTLTexture> texture;
@property (nonatomic, readonly) NSString *sourcePath;

- (instancetype)initWithTexture:(id<MTLTexture>)texture
                     sourcePath:(NSString *)sourcePath;

@end
