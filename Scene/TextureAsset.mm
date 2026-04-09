#import "TextureAsset.h"

@implementation TextureAsset

- (instancetype)initWithTexture:(id<MTLTexture>)texture
                     sourcePath:(NSString *)sourcePath {
    self = [super init];
    if (self) {
        _texture = texture;
        _sourcePath = [sourcePath copy];
    }
    return self;
}

@end
