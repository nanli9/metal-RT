#pragma once

#import <Metal/Metal.h>
#import <Foundation/Foundation.h>
#include <simd/simd.h>

@class TextureAsset;

/// Loads and deduplicates textures by file path.
/// Supports DDS (BC1/BC3/BC5) and TGA formats.
@interface TextureCache : NSObject

@property (nonatomic, readonly) NSUInteger loadedCount;
@property (nonatomic, readonly) NSUInteger failedCount;

- (instancetype)initWithDevice:(id<MTLDevice>)device;

/// Load a texture from the given absolute path, returning a cached instance
/// if already loaded. Returns nil if loading fails.
- (TextureAsset *)textureAtPath:(NSString *)path;

/// Create a 1x1 fallback texture with the given color.
- (TextureAsset *)fallbackTextureWithColor:(simd_float4)color
                                      name:(NSString *)name;

@end
