#import "DDSLoader.h"
#include <cstdint>

// DDS file format structures
// Reference: https://learn.microsoft.com/en-us/windows/win32/direct3ddds/dds-header

static const uint32_t DDS_MAGIC = 0x20534444; // "DDS "

// DDS pixel format flags
static const uint32_t DDPF_FOURCC = 0x4;

// FourCC codes
static const uint32_t FOURCC_DXT1 = 'D' | ('X' << 8) | ('T' << 16) | ('1' << 24);
static const uint32_t FOURCC_DXT5 = 'D' | ('X' << 8) | ('T' << 16) | ('5' << 24);
static const uint32_t FOURCC_ATI2 = 'A' | ('T' << 8) | ('I' << 16) | ('2' << 24);

struct DDSPixelFormat {
    uint32_t size;
    uint32_t flags;
    uint32_t fourCC;
    uint32_t rgbBitCount;
    uint32_t rBitMask;
    uint32_t gBitMask;
    uint32_t bBitMask;
    uint32_t aBitMask;
};

struct DDSHeader {
    uint32_t size;
    uint32_t flags;
    uint32_t height;
    uint32_t width;
    uint32_t pitchOrLinearSize;
    uint32_t depth;
    uint32_t mipMapCount;
    uint32_t reserved1[11];
    DDSPixelFormat pixelFormat;
    uint32_t caps;
    uint32_t caps2;
    uint32_t caps3;
    uint32_t caps4;
    uint32_t reserved2;
};

/// Returns the Metal pixel format for a given FourCC code, or MTLPixelFormatInvalid if unsupported.
/// When sRGB is true, color formats (BC1/BC3) use sRGB variants for hardware auto-linearization.
static MTLPixelFormat pixelFormatForFourCC(uint32_t fourCC, bool sRGB) {
    if (fourCC == FOURCC_DXT1) return sRGB ? MTLPixelFormatBC1_RGBA_sRGB : MTLPixelFormatBC1_RGBA;
    if (fourCC == FOURCC_DXT5) return sRGB ? MTLPixelFormatBC3_RGBA_sRGB : MTLPixelFormatBC3_RGBA;
    if (fourCC == FOURCC_ATI2) return MTLPixelFormatBC5_RGUnorm; // no sRGB variant (data texture)
    return MTLPixelFormatInvalid;
}

/// Returns the block size in bytes for a given BCn pixel format.
static NSUInteger blockSizeForFormat(MTLPixelFormat format) {
    switch (format) {
        case MTLPixelFormatBC1_RGBA:
        case MTLPixelFormatBC1_RGBA_sRGB:
            return 8;   // 4x4 block = 8 bytes
        case MTLPixelFormatBC3_RGBA:
        case MTLPixelFormatBC3_RGBA_sRGB:
            return 16;  // 4x4 block = 16 bytes
        case MTLPixelFormatBC5_RGUnorm:
            return 16;  // 4x4 block = 16 bytes
        default: return 0;
    }
}

/// Returns the byte size of a mip level for a BCn compressed texture.
static NSUInteger bytesForMipLevel(NSUInteger width, NSUInteger height, NSUInteger blockSize) {
    NSUInteger blocksWide = (width + 3) / 4;
    NSUInteger blocksHigh = (height + 3) / 4;
    return blocksWide * blocksHigh * blockSize;
}

@implementation DDSLoader

+ (id<MTLTexture>)loadTextureFromPath:(NSString *)path
                               device:(id<MTLDevice>)device
                                error:(NSError **)error
{
    return [self loadTextureFromPath:path device:device sRGB:NO error:error];
}

+ (id<MTLTexture>)loadTextureFromPath:(NSString *)path
                               device:(id<MTLDevice>)device
                                 sRGB:(BOOL)sRGB
                                error:(NSError **)error
{
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:error];
    if (!data) return nil;

    if (data.length < sizeof(uint32_t) + sizeof(DDSHeader)) {
        if (error) *error = [NSError errorWithDomain:@"DDSLoader" code:1
                            userInfo:@{NSLocalizedDescriptionKey: @"File too small to be a valid DDS"}];
        return nil;
    }

    const uint8_t *bytes = (const uint8_t *)data.bytes;

    // Verify magic number
    uint32_t magic;
    memcpy(&magic, bytes, sizeof(uint32_t));
    if (magic != DDS_MAGIC) {
        if (error) *error = [NSError errorWithDomain:@"DDSLoader" code:2
                            userInfo:@{NSLocalizedDescriptionKey: @"Not a DDS file (bad magic number)"}];
        return nil;
    }

    // Read header
    DDSHeader header;
    memcpy(&header, bytes + 4, sizeof(DDSHeader));

    // Check for FourCC format
    if (!(header.pixelFormat.flags & DDPF_FOURCC)) {
        if (error) *error = [NSError errorWithDomain:@"DDSLoader" code:3
                            userInfo:@{NSLocalizedDescriptionKey: @"Only FourCC (compressed) DDS formats are supported"}];
        return nil;
    }

    MTLPixelFormat pixelFormat = pixelFormatForFourCC(header.pixelFormat.fourCC, sRGB);
    if (pixelFormat == MTLPixelFormatInvalid) {
        char cc[5] = {};
        memcpy(cc, &header.pixelFormat.fourCC, 4);
        NSString *msg = [NSString stringWithFormat:@"Unsupported DDS FourCC: %s", cc];
        if (error) *error = [NSError errorWithDomain:@"DDSLoader" code:4
                            userInfo:@{NSLocalizedDescriptionKey: msg}];
        return nil;
    }

    NSUInteger width = header.width;
    NSUInteger height = header.height;
    NSUInteger mipCount = header.mipMapCount;
    if (mipCount == 0) mipCount = 1;

    NSUInteger blockSize = blockSizeForFormat(pixelFormat);

    // Create texture descriptor
    MTLTextureDescriptor *desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:pixelFormat
                                                                                   width:width
                                                                                  height:height
                                                                               mipmapped:(mipCount > 1)];
    desc.mipmapLevelCount = mipCount;
    desc.storageMode = MTLStorageModeShared;
    desc.usage = MTLTextureUsageShaderRead;

    id<MTLTexture> texture = [device newTextureWithDescriptor:desc];
    if (!texture) {
        if (error) *error = [NSError errorWithDomain:@"DDSLoader" code:5
                            userInfo:@{NSLocalizedDescriptionKey: @"Failed to create Metal texture"}];
        return nil;
    }

    // Upload mip levels
    NSUInteger offset = 4 + sizeof(DDSHeader); // past magic + header
    NSUInteger mipWidth = width;
    NSUInteger mipHeight = height;

    for (NSUInteger mip = 0; mip < mipCount; mip++) {
        NSUInteger bytesPerRow = ((mipWidth + 3) / 4) * blockSize;
        NSUInteger mipSize = bytesForMipLevel(mipWidth, mipHeight, blockSize);

        if (offset + mipSize > data.length) {
            NSLog(@"DDSLoader: truncated mip %lu for %@", (unsigned long)mip, path.lastPathComponent);
            break;
        }

        MTLRegion region = MTLRegionMake2D(0, 0, mipWidth, mipHeight);
        [texture replaceRegion:region
                   mipmapLevel:mip
                     withBytes:bytes + offset
                   bytesPerRow:bytesPerRow];

        offset += mipSize;
        mipWidth = MAX(mipWidth / 2, 1);
        mipHeight = MAX(mipHeight / 2, 1);
    }

    return texture;
}

@end
