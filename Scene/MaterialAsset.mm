#import "MaterialAsset.h"

@implementation MaterialAsset

- (instancetype)init {
    self = [super init];
    if (self) {
        _baseColorFactor = simd_make_float3(1, 1, 1);
        _roughnessFactor = 0.5f;
        _metallicFactor = 0.0f;
        _emissiveFactor = simd_make_float3(0, 0, 0);
        _opacity = 1.0f;
    }
    return self;
}

@end
