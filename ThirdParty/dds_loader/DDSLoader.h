#pragma once

#import <Metal/Metal.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Loads DDS files with BC1 (DXT1), BC3 (DXT5), and BC5 (ATI2) compressed formats
/// into Metal textures. Only supports macOS (BCn texture compression).
@interface DDSLoader : NSObject

/// Load a DDS file at the given path into a Metal texture.
/// Returns nil and sets error on failure.
+ (nullable id<MTLTexture>)loadTextureFromPath:(NSString *)path
                                        device:(id<MTLDevice>)device
                                         error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END
