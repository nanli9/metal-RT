#pragma once

#import <Foundation/Foundation.h>
#include <simd/simd.h>
#include <string>

@class TextureAsset;

/// Engine-owned material. Holds resolved texture references and PBR scalar parameters.
/// Format-agnostic — no dependency on import layer or FBX types.
@interface MaterialAsset : NSObject

@property (nonatomic, copy) NSString *name;

// Resolved texture assets (nil = use scalar fallback)
@property (nonatomic, strong) TextureAsset *baseColorTexture;
@property (nonatomic, strong) TextureAsset *normalTexture;
@property (nonatomic, strong) TextureAsset *specularTexture;   // ORM packed
@property (nonatomic, strong) TextureAsset *emissiveTexture;

// Scalar fallback values
@property (nonatomic) simd_float3 baseColorFactor;
@property (nonatomic) float roughnessFactor;
@property (nonatomic) float metallicFactor;
@property (nonatomic) simd_float3 emissiveFactor;
@property (nonatomic) float opacity;

@end
