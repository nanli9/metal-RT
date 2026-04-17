#import "TextureCache.h"
#import "TextureAsset.h"
#import "DDSLoader.h"
#import <MetalKit/MetalKit.h>

@implementation TextureCache {
    id<MTLDevice> _device;
    MTKTextureLoader *_mtkLoader;
    NSMutableDictionary<NSString *, TextureAsset *> *_cache;
    NSUInteger _loadedCount;
    NSUInteger _failedCount;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        _device = device;
        _mtkLoader = [[MTKTextureLoader alloc] initWithDevice:device];
        _cache = [NSMutableDictionary new];
        _loadedCount = 0;
        _failedCount = 0;
    }
    return self;
}

- (NSUInteger)loadedCount { return _loadedCount; }
- (NSUInteger)failedCount { return _failedCount; }

- (TextureAsset *)textureAtPath:(NSString *)path {
    return [self textureAtPath:path sRGB:NO];
}

- (TextureAsset *)textureAtPath:(NSString *)path sRGB:(BOOL)sRGB {
    if (!path || path.length == 0) return nil;

    // Cache key includes sRGB flag to avoid returning wrong format
    NSString *cacheKey = sRGB ? [path stringByAppendingString:@"#sRGB"] : path;
    TextureAsset *cached = _cache[cacheKey];
    if (cached) return cached;

    id<MTLTexture> texture = nil;
    NSString *ext = path.pathExtension.lowercaseString;

    if ([ext isEqualToString:@"dds"]) {
        NSError *error = nil;
        texture = [DDSLoader loadTextureFromPath:path device:_device sRGB:sRGB error:&error];
        if (!texture) {
            NSLog(@"TextureCache: failed to load DDS %@: %@", path.lastPathComponent, error.localizedDescription);
            _failedCount++;
            return nil;
        }
    } else if ([ext isEqualToString:@"tga"] || [ext isEqualToString:@"png"] || [ext isEqualToString:@"jpg"]) {
        NSURL *url = [NSURL fileURLWithPath:path];
        NSDictionary *opts = @{
            MTKTextureLoaderOptionSRGB: @(sRGB),
            MTKTextureLoaderOptionTextureStorageMode: @(MTLStorageModeShared),
            MTKTextureLoaderOptionTextureUsage: @(MTLTextureUsageShaderRead),
        };
        NSError *error = nil;
        texture = [_mtkLoader newTextureWithContentsOfURL:url options:opts error:&error];
        if (!texture) {
            NSLog(@"TextureCache: failed to load %@: %@", path.lastPathComponent, error.localizedDescription);
            _failedCount++;
            return nil;
        }
    } else {
        NSLog(@"TextureCache: unsupported format '%@' for %@", ext, path.lastPathComponent);
        _failedCount++;
        return nil;
    }

    texture.label = path.lastPathComponent;
    TextureAsset *asset = [[TextureAsset alloc] initWithTexture:texture sourcePath:path];
    _cache[cacheKey] = asset;
    _loadedCount++;
    return asset;
}

- (TextureAsset *)fallbackTextureWithColor:(simd_float4)color name:(NSString *)name {
    // Check cache by name
    NSString *key = [NSString stringWithFormat:@"__fallback__%@", name];
    TextureAsset *cached = _cache[key];
    if (cached) return cached;

    MTLTextureDescriptor *desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                   width:1
                                                                                  height:1
                                                                               mipmapped:NO];
    desc.storageMode = MTLStorageModeShared;
    desc.usage = MTLTextureUsageShaderRead;

    id<MTLTexture> texture = [_device newTextureWithDescriptor:desc];
    uint8_t pixel[4] = {
        (uint8_t)(color.x * 255.0f),
        (uint8_t)(color.y * 255.0f),
        (uint8_t)(color.z * 255.0f),
        (uint8_t)(color.w * 255.0f),
    };
    [texture replaceRegion:MTLRegionMake2D(0, 0, 1, 1)
               mipmapLevel:0
                 withBytes:pixel
               bytesPerRow:4];
    texture.label = name;

    TextureAsset *asset = [[TextureAsset alloc] initWithTexture:texture sourcePath:key];
    _cache[key] = asset;
    return asset;
}

@end
