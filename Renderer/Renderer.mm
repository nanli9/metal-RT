/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The implementation of the renderer class that performs Metal setup and per-frame rendering.
*/

#import <simd/simd.h>

#import <MetalKit/MetalKit.h>
#if __has_include(<MetalFX/MetalFX.h>)
#import <MetalFX/MetalFX.h>
#define HAS_METALFX 1
#else
#define HAS_METALFX 0
#endif
#import "Renderer.h"
#import "Transforms.h"
#import "ShaderTypes.h"
#import "Scene.h"
#import "GPUScene.h"
#import "SceneAsset.h"
#import "RenderOptions.h"

using namespace simd;

static const NSUInteger maxFramesInFlight = 3;
static const size_t alignedUniformsSize = (sizeof(Uniforms) + 255) & ~255;

@implementation Renderer
{
    id <MTLDevice> _device;
    id <MTLCommandQueue> _queue;
    id <MTLLibrary> _library;

    id <MTLBuffer> _uniformBuffer;

    id <MTLAccelerationStructure> _instanceAccelerationStructure;
    NSMutableArray *_primitiveAccelerationStructures;

    id <MTLComputePipelineState> _raytracingPipeline;
    id <MTLRenderPipelineState> _copyPipeline;

    id <MTLTexture> _accumulationTargets[2];
    id <MTLTexture> _randomTexture;

    // G-buffer textures for denoiser
    id <MTLTexture> _gbufferDepth;    // R32Float
    id <MTLTexture> _gbufferNormal;   // RGBA16Float (world-space normal)
    id <MTLTexture> _gbufferAlbedo;   // RGBA8Unorm

    // A-trous denoiser
    id <MTLComputePipelineState> _atrousDenoiserPipeline;
    id <MTLTexture> _denoiserPingPong[2]; // RGBA32Float ping-pong for iterative filtering

    // Motion vectors (for SVGF)
    id <MTLComputePipelineState> _motionVectorPipeline;
    id <MTLComputePipelineState> _debugMotionVectorPipeline;
    id <MTLTexture> _motionVectorTexture; // RG16Float

    // SVGF temporal textures
    id <MTLComputePipelineState> _svgfTemporalPipeline;
    id <MTLComputePipelineState> _svgfVariancePipeline;
    id <MTLComputePipelineState> _svgfAtrousPipeline;
    id <MTLComputePipelineState> _debugVariancePipeline;
    id <MTLTexture> _svgfColorHistory[2];   // RGBA32Float ping-pong
    id <MTLTexture> _svgfMomentHistory[2];  // RG32Float ping-pong (mean lum, mean lum^2)
    id <MTLTexture> _svgfHistoryLength[2];   // R16Float ping-pong (frames accumulated per pixel)
    id <MTLTexture> _svgfVariance;          // R32Float
    id <MTLTexture> _prevGbufferDepth;      // R32Float (previous frame)
    id <MTLTexture> _prevGbufferNormal;     // RGBA16Float (previous frame)
    unsigned int _svgfHistoryIndex;         // ping-pong index for SVGF history

    id <MTLBuffer> _resourceBuffer;
    id <MTLBuffer> _instanceBuffer;

    id <MTLIntersectionFunctionTable> _intersectionFunctionTable;

    dispatch_semaphore_t _sem;
    CGSize _size;
    NSUInteger _uniformBufferOffset;
    NSUInteger _uniformBufferIndex;

    unsigned int _frameIndex;

    Scene *_scene;

    NSUInteger _resourcesStride;
    bool _useIntersectionFunctions;
    bool _usePerPrimitiveData;

    // Bistro/GPUScene path
    GPUScene *_gpuScene;
    SceneAsset *_sceneAsset;
    bool _useBistroPath;

    id<MTLBuffer> _textureArgBuffer;

    // View-projection matrices for SVGF motion vectors
    matrix_float4x4 _prevViewProjectionMatrix;
    bool _hasPrevViewProjectionMatrix;
    bool _svgfNeedsClear; // flag to clear SVGF history on next frame

    // MetalFX Temporal Upscaling
#if HAS_METALFX
    id<MTLFXTemporalScaler> _metalFXScaler;
#endif
    id<MTLTexture> _metalFXColorInput;   // RGBA16Float at internal resolution
    id<MTLTexture> _upscaledOutput;      // RGBA16Float at display resolution
    id <MTLComputePipelineState> _formatConvertPipeline;
    bool _metalFXSupported;
    bool _metalFXNeedsRecreate;
    CGSize _displaySize;
    CGSize _internalSize;
    float _currentJitterX;
    float _currentJitterY;
}

- (nonnull instancetype)initWithDevice:(nonnull id<MTLDevice>)device
                                 scene:(Scene *)scene
{
    self = [super init];

    if (self)
    {
        _device = device;

        _sem = dispatch_semaphore_create(maxFramesInFlight);

        _scene = scene;

        [self loadMetal];
        [self createBuffers];
        [self createAccelerationStructures];
        [self createPipelines];
        [self detectMetalFXSupport];
    }

    return self;
}

- (nonnull instancetype)initWithDevice:(nonnull id<MTLDevice>)device
                              gpuScene:(GPUScene *)gpuScene
                            sceneAsset:(SceneAsset *)sceneAsset
{
    self = [super init];

    if (self)
    {
        _device = device;
        _sem = dispatch_semaphore_create(maxFramesInFlight);
        _gpuScene = gpuScene;
        _sceneAsset = sceneAsset;
        _useBistroPath = YES;

        _cameraPosition = sceneAsset.cameraPosition;
        _cameraTarget = sceneAsset.cameraTarget;

        [self loadMetal];
        [self createBistroBuffers];
        [self createBistroPipelines];
        [self detectMetalFXSupport];
    }

    return self;
}

- (void)resetAccumulation {
    _frameIndex = 0;
    _svgfNeedsClear = true;
    _hasPrevViewProjectionMatrix = false;
}

- (id<MTLCommandQueue>)commandQueue {
    return _queue;
}

- (void)detectMetalFXSupport {
#if HAS_METALFX
    if (@available(macOS 13.0, *)) {
        _metalFXSupported = [MTLFXTemporalScalerDescriptor supportsDevice:_device];
        NSLog(@"MetalFX Temporal Scaler supported: %@", _metalFXSupported ? @"YES" : @"NO");
    } else {
        _metalFXSupported = false;
    }
#else
    _metalFXSupported = false;
#endif
}

- (bool)metalFXSupported {
    return _metalFXSupported;
}

- (void)recreateMetalFXScaler {
#if HAS_METALFX
    if (@available(macOS 13.0, *)) {
        MTLFXTemporalScalerDescriptor *desc = [[MTLFXTemporalScalerDescriptor alloc] init];
        desc.inputWidth = (NSUInteger)_internalSize.width;
        desc.inputHeight = (NSUInteger)_internalSize.height;
        desc.outputWidth = (NSUInteger)_displaySize.width;
        desc.outputHeight = (NSUInteger)_displaySize.height;
        desc.colorTextureFormat = MTLPixelFormatRGBA16Float;
        desc.depthTextureFormat = MTLPixelFormatR32Float;
        desc.motionTextureFormat = MTLPixelFormatRG16Float;
        desc.outputTextureFormat = MTLPixelFormatRGBA16Float;
        desc.autoExposureEnabled = NO;

        _metalFXScaler = [desc newTemporalScalerWithDevice:_device];
        if (_metalFXScaler) {
            // Motion vectors are in pixel units; MetalFX scales them by these values
            // to convert to UV-space (0..1). So we set scale = internalSize.
            _metalFXScaler.motionVectorScaleX = (float)_internalSize.width;
            _metalFXScaler.motionVectorScaleY = (float)_internalSize.height;
            NSLog(@"MetalFX scaler created: %dx%d → %dx%d",
                  (int)_internalSize.width, (int)_internalSize.height,
                  (int)_displaySize.width, (int)_displaySize.height);
        } else {
            NSLog(@"Failed to create MetalFX temporal scaler");
        }
    }
#endif
}

// Initialize the Metal shader library and command queue.
- (void)loadMetal
{
    _library = [_device newDefaultLibrary];

    _queue = [_device newCommandQueue];
}

// Create a compute pipeline state with an optional array of additional functions to link the compute
// function with. The sample uses this to link the ray-tracing kernel with any intersection functions.
- (id <MTLComputePipelineState>)newComputePipelineStateWithFunction:(id <MTLFunction>)function
                                                    linkedFunctions:(NSArray <id <MTLFunction>> *)linkedFunctions
{
    MTLLinkedFunctions *mtlLinkedFunctions = nil;

    // Attach the additional functions to an MTLLinkedFunctions object
    if (linkedFunctions) {
        mtlLinkedFunctions = [[MTLLinkedFunctions alloc] init];

        mtlLinkedFunctions.functions = linkedFunctions;
    }

    MTLComputePipelineDescriptor *descriptor = [[MTLComputePipelineDescriptor alloc] init];

    // Set the main compute function.
    descriptor.computeFunction = function;

    // Attach the linked functions object to the compute pipeline descriptor.
    descriptor.linkedFunctions = mtlLinkedFunctions;

    // Set to YES to allow the compiler to make certain optimizations.
    descriptor.threadGroupSizeIsMultipleOfThreadExecutionWidth = YES;

    NSError *error;

    // Create the compute pipeline state.
    id <MTLComputePipelineState> pipeline = [_device newComputePipelineStateWithDescriptor:descriptor
                                                                                   options:0
                                                                                reflection:nil
                                                                                     error:&error];
    NSAssert(pipeline, @"Failed to create %@ pipeline state: %@", function.name, error);

    return pipeline;
}

// Create a compute function, and specialize its function constants.
- (id <MTLFunction>)specializedFunctionWithName:(NSString *)name {
    // Fill out a dictionary of function constant values.
    MTLFunctionConstantValues *constants = [[MTLFunctionConstantValues alloc] init];

    // The first constant is the stride between entries in the resource buffer. The sample
    // uses this stride to allow intersection functions to look up any resources they use.
    uint32_t resourcesStride = (uint32_t)_resourcesStride;
    [constants setConstantValue:&resourcesStride type:MTLDataTypeUInt atIndex:0];

    // The second constant turns the use of intersection functions on and off.
    [constants setConstantValue:&_useIntersectionFunctions type:MTLDataTypeBool atIndex:1];

    // The third constant turns the use of per-primitive data on and off.
    [constants setConstantValue:&_usePerPrimitiveData type:MTLDataTypeBool atIndex:2];

    // The fourth constant enables the Bistro/GPUScene path.
    bool bistroMode = _useBistroPath;
    [constants setConstantValue:&bistroMode type:MTLDataTypeBool atIndex:3];

    NSError *error;

    // Load the function from the Metal library.
    id <MTLFunction> function = [_library newFunctionWithName:name constantValues:constants error:&error];

    NSAssert(function, @"Failed to create function %@: %@", name, error, function.name, error);

    return function;
}

// Create pipeline states.
- (void)createPipelines
{
    _useIntersectionFunctions = false;
#if SUPPORTS_METAL_3
    _usePerPrimitiveData = true;
#else
    _usePerPrimitiveData = false;
#endif

    // Check if any scene geometry has an intersection function.
    for (Geometry *geometry in _scene.geometries) {
        if (geometry.intersectionFunctionName) {
            _useIntersectionFunctions = true;
            break;
        }
    }

    // Maps intersection function names to actual MTLFunctions.
    NSMutableDictionary <NSString *, id <MTLFunction>> *intersectionFunctions = [NSMutableDictionary dictionary];

    // First, load all the intersection functions because the sample needs them to create the final
    // ray-tracing compute pipeline state.
    for (Geometry *geometry in _scene.geometries) {
        // Skip if the geometry doesn't have an intersection function or if the app already loaded
        // it.
        if (!geometry.intersectionFunctionName || [intersectionFunctions objectForKey:geometry.intersectionFunctionName])
            continue;

        // Specialize function constants the intersection function uses.
        id <MTLFunction> intersectionFunction = [self specializedFunctionWithName:geometry.intersectionFunctionName];

        // Add the function to the dictionary.
        intersectionFunctions[geometry.intersectionFunctionName] = intersectionFunction;
    }

    id <MTLFunction> raytracingFunction = [self specializedFunctionWithName:@"raytracingKernel"];

    // Create the compute pipeline state, which does all the ray tracing.
    _raytracingPipeline = [self newComputePipelineStateWithFunction:raytracingFunction
                                                    linkedFunctions:[intersectionFunctions allValues]];

    // Create the intersection function table.
    if (_useIntersectionFunctions) {
        MTLIntersectionFunctionTableDescriptor *intersectionFunctionTableDescriptor = [[MTLIntersectionFunctionTableDescriptor alloc] init];

        intersectionFunctionTableDescriptor.functionCount = _scene.geometries.count;

        // Create a table large enough to hold all of the intersection functions. Metal
        // links intersection functions into the compute pipeline state, potentially with
        // a different address for each compute pipeline. Therefore, the intersection
        // function table is specific to the compute pipeline state that created it, and you
        // can use it with only that pipeline.
        _intersectionFunctionTable = [_raytracingPipeline newIntersectionFunctionTableWithDescriptor:intersectionFunctionTableDescriptor];

        if (!_usePerPrimitiveData) {
            // Bind the buffer used to pass resources to the intersection functions.
            [_intersectionFunctionTable setBuffer:_resourceBuffer offset:0 atIndex:0];
        }

        // Map each piece of scene geometry to its intersection function.
        for (NSUInteger geometryIndex = 0; geometryIndex < _scene.geometries.count; geometryIndex++) {
            Geometry *geometry = _scene.geometries[geometryIndex];

            if (geometry.intersectionFunctionName) {
                id <MTLFunction> intersectionFunction = intersectionFunctions[geometry.intersectionFunctionName];

                // Create a handle to the copy of the intersection function linked into the
                // ray-tracing compute pipeline state. Create a different handle for each pipeline
                // it is linked with.
                id <MTLFunctionHandle> handle = [_raytracingPipeline functionHandleWithFunction:intersectionFunction];

                // Insert the handle into the intersection function table, which ultimately maps the
                // geometry's index to its intersection function.
                [_intersectionFunctionTable setFunction:handle atIndex:geometryIndex];
            }
        }
    }

    // Create a render pipeline state that copies the rendered scene into the MTKView and
    // performs simple tone mapping.
    MTLRenderPipelineDescriptor *renderDescriptor = [[MTLRenderPipelineDescriptor alloc] init];

    renderDescriptor.vertexFunction = [_library newFunctionWithName:@"copyVertex"];
    renderDescriptor.fragmentFunction = [_library newFunctionWithName:@"copyFragment"];

    renderDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA16Float;

    NSError *error;

    _copyPipeline = [_device newRenderPipelineStateWithDescriptor:renderDescriptor error:&error];

    NSAssert(_copyPipeline, @"Failed to create the copy pipeline state %@: %@", raytracingFunction.name, error);

    // A-trous denoiser pipeline
    id<MTLFunction> atrousFunction = [_library newFunctionWithName:@"atrousDenoiser"];
    NSAssert(atrousFunction, @"Failed to find atrousDenoiser function");
    _atrousDenoiserPipeline = [_device newComputePipelineStateWithFunction:atrousFunction error:&error];
    NSAssert(_atrousDenoiserPipeline, @"Failed to create A-trous denoiser pipeline: %@", error);

    // Motion vector pipeline
    id<MTLFunction> motionFunction = [_library newFunctionWithName:@"computeMotionVectors"];
    NSAssert(motionFunction, @"Failed to find computeMotionVectors function");
    _motionVectorPipeline = [_device newComputePipelineStateWithFunction:motionFunction error:&error];
    NSAssert(_motionVectorPipeline, @"Failed to create motion vector pipeline: %@", error);

    id<MTLFunction> debugMVFunction = [_library newFunctionWithName:@"debugMotionVectors"];
    _debugMotionVectorPipeline = [_device newComputePipelineStateWithFunction:debugMVFunction error:&error];

    [self createSVGFPipelines];
}

- (void)createSVGFPipelines {
    NSError *error;
    id<MTLFunction> fn;

    fn = [_library newFunctionWithName:@"svgfTemporalAccumulation"];
    NSAssert(fn, @"Failed to find svgfTemporalAccumulation");
    _svgfTemporalPipeline = [_device newComputePipelineStateWithFunction:fn error:&error];
    NSAssert(_svgfTemporalPipeline, @"Failed to create SVGF temporal pipeline: %@", error);

    fn = [_library newFunctionWithName:@"svgfEstimateVariance"];
    if (fn) {
        _svgfVariancePipeline = [_device newComputePipelineStateWithFunction:fn error:&error];
    }

    fn = [_library newFunctionWithName:@"svgfAtrousFilter"];
    if (fn) {
        _svgfAtrousPipeline = [_device newComputePipelineStateWithFunction:fn error:&error];
    }

    fn = [_library newFunctionWithName:@"debugVariance"];
    if (fn) {
        _debugVariancePipeline = [_device newComputePipelineStateWithFunction:fn error:&error];
    }

    fn = [_library newFunctionWithName:@"formatConvert32to16"];
    if (fn) {
        _formatConvertPipeline = [_device newComputePipelineStateWithFunction:fn error:&error];
    }
}

// Create an argument encoder that encodes references to a set of resources into a buffer.
- (id <MTLArgumentEncoder>)newArgumentEncoderForResources:(NSArray <id <MTLResource>> *)resources {
    NSMutableArray *arguments = [NSMutableArray array];

    for (id <MTLResource> resource in resources) {
        MTLArgumentDescriptor *argumentDescriptor = [MTLArgumentDescriptor argumentDescriptor];

        argumentDescriptor.index = arguments.count;
        argumentDescriptor.access = MTLBindingAccessReadOnly;

        if ([resource conformsToProtocol:@protocol(MTLBuffer)])
            argumentDescriptor.dataType = MTLDataTypePointer;
        else if ([resource conformsToProtocol:@protocol(MTLTexture)]) {
            id <MTLTexture> texture = (id <MTLTexture>)resource;

            argumentDescriptor.dataType = MTLDataTypeTexture;
            argumentDescriptor.textureType = texture.textureType;
        }

        [arguments addObject:argumentDescriptor];
    }

    return [_device newArgumentEncoderWithArguments:arguments];
}

- (void)createBuffers {
    // The uniform buffer contains a few small values, which change from frame to frame. The
    // sample can have up to three frames in flight at the same time, so allocate a range of the buffer
    // for each frame. The GPU reads from one chunk while the CPU writes to the next chunk.
    // Align the chunks to 256 bytes on macOS and 16 bytes on iOS.
    NSUInteger uniformBufferSize = alignedUniformsSize * maxFramesInFlight;

    MTLResourceOptions options = getManagedBufferStorageMode();

    _uniformBuffer = [_device newBufferWithLength:uniformBufferSize options:options];

    // Upload scene data to buffers.
    [_scene uploadToBuffers];

    _resourcesStride = 0;

    // Each intersection function has its own set of resources. Determine the maximum size over all
    // intersection functions. This size becomes the stride that intersection functions use to find
    // the starting address for their resources.
    for (Geometry *geometry in _scene.geometries) {
#if SUPPORTS_METAL_3
        if (geometry.resources.count * sizeof(uint64_t) > _resourcesStride)
            _resourcesStride = geometry.resources.count * sizeof(uint64_t);
#else
        id <MTLArgumentEncoder> encoder = [self newArgumentEncoderForResources:geometry.resources];

        if (encoder.encodedLength > _resourcesStride)
            _resourcesStride = encoder.encodedLength;
#endif
    }

    // Create the resource buffer.
    _resourceBuffer = [_device newBufferWithLength:_resourcesStride * _scene.geometries.count options:options];

    for (NSUInteger geometryIndex = 0; geometryIndex < _scene.geometries.count; geometryIndex++) {
        Geometry *geometry = _scene.geometries[geometryIndex];

#if SUPPORTS_METAL_3
        // Retrieve the list of arguments for this geometry's intersection function's resources.
        NSArray<id <MTLResource>>* resources = [geometry resources];

        // Get a pointer to the resource buffer.
        // Resources can return a gpuAddress or gpuResourceID, which are both the same size as a uint64_t.
        uint64_t *resourceHandles = (uint64_t*)((uint8_t*)_resourceBuffer.contents + _resourcesStride * geometryIndex);

        // Encode the arguments into the resource buffer.
        for (NSUInteger argumentIndex = 0; argumentIndex < resources.count; argumentIndex++) {
            id <MTLResource> resource = resources[argumentIndex];
            if ([resource conformsToProtocol:@protocol(MTLBuffer)])
                resourceHandles[argumentIndex] = [(id <MTLBuffer>)resource gpuAddress];
            else if ([resource conformsToProtocol:@protocol(MTLTexture)])
                *((MTLResourceID*)(resourceHandles + argumentIndex)) = [(id <MTLTexture>)resource gpuResourceID];
        }
#else
        // Create an argument encoder for this geometry's intersection function's resources.
        id <MTLArgumentEncoder> encoder = [self newArgumentEncoderForResources:geometry.resources];

        // Bind the argument encoder to the resource buffer at this geometry's offset.
        [encoder setArgumentBuffer:_resourceBuffer offset:_resourcesStride * geometryIndex];

        // Encode the arguments into the resource buffer.
        for (NSUInteger argumentIndex = 0; argumentIndex < geometry.resources.count; argumentIndex++) {
            id <MTLResource> resource = geometry.resources[argumentIndex];

            if ([resource conformsToProtocol:@protocol(MTLBuffer)])
                [encoder setBuffer:(id <MTLBuffer>)resource offset:0 atIndex:argumentIndex];
            else if ([resource conformsToProtocol:@protocol(MTLTexture)])
                [encoder setTexture:(id <MTLTexture>)resource atIndex:argumentIndex];
        }
#endif
    }

#if !TARGET_OS_IPHONE
    [_resourceBuffer didModifyRange:NSMakeRange(0, _resourceBuffer.length)];
#endif
}

// Create and compact an acceleration structure, given an acceleration structure descriptor.
- (id <MTLAccelerationStructure>)newAccelerationStructureWithDescriptor:(MTLAccelerationStructureDescriptor *)descriptor
{
    // Query for the sizes needed to store and build the acceleration structure.
    MTLAccelerationStructureSizes accelSizes = [_device accelerationStructureSizesWithDescriptor:descriptor];

    // Allocate an acceleration structure large enough for this descriptor. This method
    // doesn't actually build the acceleration structure, but rather allocates memory.
    id <MTLAccelerationStructure> accelerationStructure = [_device newAccelerationStructureWithSize:accelSizes.accelerationStructureSize];

    // Allocate scratch space Metal uses to build the acceleration structure.
    // Use MTLResourceStorageModePrivate for the best performance because the sample
    // doesn't need access to buffer's contents.
    id <MTLBuffer> scratchBuffer = [_device newBufferWithLength:accelSizes.buildScratchBufferSize options:MTLResourceStorageModePrivate];

    // Create a command buffer that performs the acceleration structure build.
    id <MTLCommandBuffer> commandBuffer = [_queue commandBuffer];

    // Create an acceleration structure command encoder.
    id <MTLAccelerationStructureCommandEncoder> commandEncoder = [commandBuffer accelerationStructureCommandEncoder];

    // Allocate a buffer for Metal to write the compacted accelerated structure's size into.
    id <MTLBuffer> compactedSizeBuffer = [_device newBufferWithLength:sizeof(uint32_t) options:MTLResourceStorageModeShared];

    // Schedule the actual acceleration structure build.
    [commandEncoder buildAccelerationStructure:accelerationStructure
                                    descriptor:descriptor
                                 scratchBuffer:scratchBuffer
                           scratchBufferOffset:0];

    // Compute and write the compacted acceleration structure size into the buffer. You
    // must already have a built acceleration structure because Metal determines the compacted
    // size based on the final size of the acceleration structure. Compacting an acceleration
    // structure can potentially reclaim significant amounts of memory because Metal must
    // create the initial structure using a conservative approach.

    [commandEncoder writeCompactedAccelerationStructureSize:accelerationStructure
                                                   toBuffer:compactedSizeBuffer
                                                     offset:0];

    // End encoding, and commit the command buffer so the GPU can start building the
    // acceleration structure.
    [commandEncoder endEncoding];

    [commandBuffer commit];

    // The sample waits for Metal to finish executing the command buffer so that it can
    // read back the compacted size.

    // Note: Don't wait for Metal to finish executing the command buffer if you aren't compacting
    // the acceleration structure, as doing so requires CPU/GPU synchronization. You don't have
    // to compact acceleration structures, but do so when creating large static acceleration
    // structures, such as static scene geometry. Avoid compacting acceleration structures that
    // you rebuild every frame, as the synchronization cost may be significant.

    [commandBuffer waitUntilCompleted];

    uint32_t compactedSize = *(uint32_t *)compactedSizeBuffer.contents;

    // Allocate a smaller acceleration structure based on the returned size.
    id <MTLAccelerationStructure> compactedAccelerationStructure = [_device newAccelerationStructureWithSize:compactedSize];

    // Create another command buffer and encoder.
    commandBuffer = [_queue commandBuffer];

    commandEncoder = [commandBuffer accelerationStructureCommandEncoder];

    // Encode the command to copy and compact the acceleration structure into the
    // smaller acceleration structure.
    [commandEncoder copyAndCompactAccelerationStructure:accelerationStructure
                                toAccelerationStructure:compactedAccelerationStructure];

    // End encoding and commit the command buffer. You don't need to wait for Metal to finish
    // executing this command buffer as long as you synchronize any ray-intersection work
    // to run after this command buffer completes. The sample relies on Metal's default
    // dependency tracking on resources to automatically synchronize access to the new
    // compacted acceleration structure.
    [commandEncoder endEncoding];
    [commandBuffer commit];

    return compactedAccelerationStructure;
}

// Create acceleration structures for the scene. The scene contains primitive acceleration
// structures and an instance acceleration structure. The primitive acceleration structures
// contain primitives, such as triangles and spheres. The instance acceleration structure contains
// copies, or instances, of the primitive acceleration structures, each with their own
// transformation matrix that describes where to place them in the scene.
- (void)createAccelerationStructures
{
    MTLResourceOptions options = getManagedBufferStorageMode();

    _primitiveAccelerationStructures = [[NSMutableArray alloc] init];

    // Create a primitive acceleration structure for each piece of geometry in the scene.
    for (NSUInteger i = 0; i < _scene.geometries.count; i++) {
        Geometry *mesh = _scene.geometries[i];

        MTLAccelerationStructureGeometryDescriptor *geometryDescriptor = [mesh geometryDescriptor];

        // Assign each piece of geometry a consecutive slot in the intersection function table.
        geometryDescriptor.intersectionFunctionTableOffset = i;

        // Create a primitive acceleration structure descriptor to contain the single piece
        // of acceleration structure geometry.
        MTLPrimitiveAccelerationStructureDescriptor *accelDescriptor = [MTLPrimitiveAccelerationStructureDescriptor descriptor];

        accelDescriptor.geometryDescriptors = @[ geometryDescriptor ];

        // Build the acceleration structure.
        id <MTLAccelerationStructure> accelerationStructure = [self newAccelerationStructureWithDescriptor:accelDescriptor];

        // Add the acceleration structure to the array of primitive acceleration structures.
        [_primitiveAccelerationStructures addObject:accelerationStructure];
    }

    // Allocate a buffer of acceleration structure instance descriptors. Each descriptor represents
    // an instance of one of the primitive acceleration structures created above, with its own
    // transformation matrix.
    _instanceBuffer = [_device newBufferWithLength:sizeof(MTLAccelerationStructureInstanceDescriptor) * _scene.instances.count options:options];

    MTLAccelerationStructureInstanceDescriptor *instanceDescriptors = (MTLAccelerationStructureInstanceDescriptor *)_instanceBuffer.contents;

    // Fill out instance descriptors.
    for (NSUInteger instanceIndex = 0; instanceIndex < _scene.instances.count; instanceIndex++) {
        GeometryInstance *instance = _scene.instances[instanceIndex];

        NSUInteger geometryIndex = [_scene.geometries indexOfObject:instance.geometry];

        // Map the instance to its acceleration structure.
        instanceDescriptors[instanceIndex].accelerationStructureIndex = (uint32_t)geometryIndex;

        // Mark the instance as opaque if it doesn't have an intersection function so that the
        // ray intersector doesn't attempt to execute a function that doesn't exist.
        instanceDescriptors[instanceIndex].options = instance.geometry.intersectionFunctionName == nil ? MTLAccelerationStructureInstanceOptionOpaque : 0;

        // Metal adds the geometry intersection function table offset and instance intersection
        // function table offset together to determine which intersection function to execute.
        // The sample mapped geometries directly to their intersection functions above, so it
        // sets the instance's table offset to 0.
        instanceDescriptors[instanceIndex].intersectionFunctionTableOffset = 0;

        // Set the instance mask, which the sample uses to filter out intersections between rays
        // and geometry. For example, it uses masks to prevent light sources from being visible
        // to secondary rays, which would result in their contribution being double-counted.
        instanceDescriptors[instanceIndex].mask = (uint32_t)instance.mask;

        // Copy the first three rows of the instance transformation matrix. Metal
        // assumes that the bottom row is (0, 0, 0, 1), which allows the renderer to
        // tightly pack instance descriptors in memory.
        for (int column = 0; column < 4; column++)
            for (int row = 0; row < 3; row++)
                instanceDescriptors[instanceIndex].transformationMatrix.columns[column][row] = instance.transform.columns[column][row];
    }

#if !TARGET_OS_IPHONE
    [_instanceBuffer didModifyRange:NSMakeRange(0, _instanceBuffer.length)];
#endif

    // Create an instance acceleration structure descriptor.
    MTLInstanceAccelerationStructureDescriptor *accelDescriptor = [MTLInstanceAccelerationStructureDescriptor descriptor];

    accelDescriptor.instancedAccelerationStructures = _primitiveAccelerationStructures;
    accelDescriptor.instanceCount = _scene.instances.count;
    accelDescriptor.instanceDescriptorBuffer = _instanceBuffer;

    // Create the instance acceleration structure that contains all instances in the scene.
    _instanceAccelerationStructure = [self newAccelerationStructureWithDescriptor:accelDescriptor];
}

// ---- Bistro/GPUScene pipeline setup ----

- (void)createBistroBuffers {
    NSUInteger uniformBufferSize = alignedUniformsSize * maxFramesInFlight;
    _uniformBuffer = [_device newBufferWithLength:uniformBufferSize options:getManagedBufferStorageMode()];

    // Build argument buffer for bindless texture access
    [self createTextureArgBuffer];
}

- (void)createTextureArgBuffer {
    NSArray<id<MTLTexture>> *textures = _gpuScene.textures;
    if (textures.count == 0) return;

    // Use MTLArgumentEncoder to properly encode textures into the argument buffer.
    // Get the encoder from the kernel function's buffer(7) binding.
    id<MTLFunction> kernelFn = [_library newFunctionWithName:@"raytracingKernel"
                                              constantValues:[self bistroPipelineConstants]
                                                       error:nil];
    id<MTLArgumentEncoder> encoder = [kernelFn newArgumentEncoderWithBufferIndex:7];

    NSUInteger argBufSize = encoder.encodedLength;
    _textureArgBuffer = [_device newBufferWithLength:argBufSize options:MTLResourceStorageModeShared];
    _textureArgBuffer.label = @"Texture Argument Buffer";

    [encoder setArgumentBuffer:_textureArgBuffer offset:0];
    for (NSUInteger i = 0; i < textures.count; i++) {
        [encoder setTexture:textures[i] atIndex:i];
    }

    NSLog(@"Renderer: created texture argument buffer — %lu textures, %lu bytes",
          (unsigned long)textures.count, (unsigned long)argBufSize);
}


- (MTLFunctionConstantValues *)bistroPipelineConstants {
    MTLFunctionConstantValues *constants = [[MTLFunctionConstantValues alloc] init];
    uint32_t resourcesStride = 0;
    [constants setConstantValue:&resourcesStride type:MTLDataTypeUInt atIndex:0];
    bool noIntersectionFunctions = false;
    [constants setConstantValue:&noIntersectionFunctions type:MTLDataTypeBool atIndex:1];
    bool perPrimitiveData = true;
    [constants setConstantValue:&perPrimitiveData type:MTLDataTypeBool atIndex:2];
    bool bMode = true;
    [constants setConstantValue:&bMode type:MTLDataTypeBool atIndex:3];
    return constants;
}

- (void)createBistroPipelines {
    _useIntersectionFunctions = false;
    _usePerPrimitiveData = true;
    _resourcesStride = 0;

    NSError *error;
    id<MTLFunction> raytracingFunction = [_library newFunctionWithName:@"raytracingKernel"
                                                        constantValues:[self bistroPipelineConstants]
                                                                 error:&error];
    NSAssert(raytracingFunction, @"Failed to create bistro raytracing function: %@", error);

    MTLComputePipelineDescriptor *descriptor = [[MTLComputePipelineDescriptor alloc] init];
    descriptor.computeFunction = raytracingFunction;
    descriptor.threadGroupSizeIsMultipleOfThreadExecutionWidth = YES;

    _raytracingPipeline = [_device newComputePipelineStateWithDescriptor:descriptor
                                                                 options:0
                                                              reflection:nil
                                                                   error:&error];
    NSAssert(_raytracingPipeline, @"Failed to create bistro raytracing pipeline: %@", error);

    // Copy pipeline (same as original)
    MTLRenderPipelineDescriptor *renderDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    renderDescriptor.vertexFunction = [_library newFunctionWithName:@"copyVertex"];
    renderDescriptor.fragmentFunction = [_library newFunctionWithName:@"copyFragment"];
    renderDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA16Float;

    _copyPipeline = [_device newRenderPipelineStateWithDescriptor:renderDescriptor error:&error];
    NSAssert(_copyPipeline, @"Failed to create copy pipeline: %@", error);

    // A-trous denoiser pipeline
    id<MTLFunction> atrousFunction = [_library newFunctionWithName:@"atrousDenoiser"];
    NSAssert(atrousFunction, @"Failed to find atrousDenoiser function");
    _atrousDenoiserPipeline = [_device newComputePipelineStateWithFunction:atrousFunction error:&error];
    NSAssert(_atrousDenoiserPipeline, @"Failed to create A-trous denoiser pipeline: %@", error);

    // Motion vector pipeline
    id<MTLFunction> motionFunction = [_library newFunctionWithName:@"computeMotionVectors"];
    NSAssert(motionFunction, @"Failed to find computeMotionVectors function");
    _motionVectorPipeline = [_device newComputePipelineStateWithFunction:motionFunction error:&error];
    NSAssert(_motionVectorPipeline, @"Failed to create motion vector pipeline: %@", error);

    id<MTLFunction> debugMVFunction = [_library newFunctionWithName:@"debugMotionVectors"];
    _debugMotionVectorPipeline = [_device newComputePipelineStateWithFunction:debugMVFunction error:&error];

    [self createSVGFPipelines];
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size
{
    _displaySize = size;

    // Compute internal render resolution for MetalFX upscaling
    bool useMetalFX = _renderOptions.enableMetalFXUpscaling && _metalFXSupported;
    if (useMetalFX) {
        float ratio = fmax(_renderOptions.upscaleRatio, 0.25f);
        _internalSize = CGSizeMake(fmax(size.width * ratio, 1.0),
                                    fmax(size.height * ratio, 1.0));
    } else {
        _internalSize = size;
    }
    _size = _internalSize; // _size is used for dispatch calculations

    // Create a pair of textures that the ray tracing kernel uses to accumulate
    // samples over several frames.
    MTLTextureDescriptor *textureDescriptor = [[MTLTextureDescriptor alloc] init];

    textureDescriptor.pixelFormat = MTLPixelFormatRGBA32Float;
    textureDescriptor.textureType = MTLTextureType2D;
    textureDescriptor.width = _internalSize.width;
    textureDescriptor.height = _internalSize.height;

    // Store the texture in private memory because only the GPU reads or writes this texture.
    textureDescriptor.storageMode = MTLStorageModePrivate;
    textureDescriptor.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;

    for (NSUInteger i = 0; i < 2; i++)
        _accumulationTargets[i] = [_device newTextureWithDescriptor:textureDescriptor];

    // G-buffer textures for denoiser (all GPU-private, read+write)
    textureDescriptor.pixelFormat = MTLPixelFormatR32Float;
    _gbufferDepth = [_device newTextureWithDescriptor:textureDescriptor];

    textureDescriptor.pixelFormat = MTLPixelFormatRGBA16Float;
    _gbufferNormal = [_device newTextureWithDescriptor:textureDescriptor];

    textureDescriptor.pixelFormat = MTLPixelFormatRGBA8Unorm;
    _gbufferAlbedo = [_device newTextureWithDescriptor:textureDescriptor];

    // Motion vector texture (screen-space 2D vectors in pixels)
    textureDescriptor.pixelFormat = MTLPixelFormatRG16Float;
    _motionVectorTexture = [_device newTextureWithDescriptor:textureDescriptor];

    // Denoiser ping-pong textures (same format as accumulation targets)
    textureDescriptor.pixelFormat = MTLPixelFormatRGBA32Float;
    for (NSUInteger i = 0; i < 2; i++)
        _denoiserPingPong[i] = [_device newTextureWithDescriptor:textureDescriptor];

    // SVGF temporal textures
    textureDescriptor.pixelFormat = MTLPixelFormatRGBA32Float;
    for (NSUInteger i = 0; i < 2; i++)
        _svgfColorHistory[i] = [_device newTextureWithDescriptor:textureDescriptor];

    textureDescriptor.pixelFormat = MTLPixelFormatRG32Float;
    for (NSUInteger i = 0; i < 2; i++)
        _svgfMomentHistory[i] = [_device newTextureWithDescriptor:textureDescriptor];

    textureDescriptor.pixelFormat = MTLPixelFormatR16Float;
    for (NSUInteger i = 0; i < 2; i++)
        _svgfHistoryLength[i] = [_device newTextureWithDescriptor:textureDescriptor];

    textureDescriptor.pixelFormat = MTLPixelFormatR32Float;
    _svgfVariance = [_device newTextureWithDescriptor:textureDescriptor];

    // Previous frame G-buffer copies (for SVGF temporal validation)
    textureDescriptor.pixelFormat = MTLPixelFormatR32Float;
    _prevGbufferDepth = [_device newTextureWithDescriptor:textureDescriptor];

    textureDescriptor.pixelFormat = MTLPixelFormatRGBA16Float;
    _prevGbufferNormal = [_device newTextureWithDescriptor:textureDescriptor];

    _svgfHistoryIndex = 0;

    // Create a texture that contains a random integer value for each pixel. The sample
    // uses these values to decorrelate pixels while drawing pseudorandom numbers from the
    // Halton sequence.
    textureDescriptor.pixelFormat = MTLPixelFormatR32Uint;
    textureDescriptor.usage = MTLTextureUsageShaderRead;

    // The sample initializes the data in the texture, so it can't be private.
#if !TARGET_OS_IPHONE
    textureDescriptor.storageMode = MTLStorageModeManaged;
#else
    textureDescriptor.storageMode = MTLStorageModeShared;
#endif

    _randomTexture = [_device newTextureWithDescriptor:textureDescriptor];

    // Initialize random values.
    NSUInteger rw = (NSUInteger)_internalSize.width;
    NSUInteger rh = (NSUInteger)_internalSize.height;
    uint32_t *randomValues = (uint32_t *)malloc(sizeof(uint32_t) * rw * rh);

    for (NSUInteger i = 0; i < rw * rh; i++)
        randomValues[i] = rand() % (1024 * 1024);

    [_randomTexture replaceRegion:MTLRegionMake2D(0, 0, rw, rh)
                      mipmapLevel:0
                        withBytes:randomValues
                      bytesPerRow:sizeof(uint32_t) * rw];

    free(randomValues);

    // MetalFX upscaling textures
    if (useMetalFX) {
        MTLTextureDescriptor *mfxDesc = [[MTLTextureDescriptor alloc] init];
        mfxDesc.textureType = MTLTextureType2D;
        mfxDesc.storageMode = MTLStorageModePrivate;
        mfxDesc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;

        // Color input for MetalFX at internal resolution (RGBA16Float required)
        mfxDesc.pixelFormat = MTLPixelFormatRGBA16Float;
        mfxDesc.width = _internalSize.width;
        mfxDesc.height = _internalSize.height;
        _metalFXColorInput = [_device newTextureWithDescriptor:mfxDesc];

        // Upscaled output at display resolution
        mfxDesc.width = _displaySize.width;
        mfxDesc.height = _displaySize.height;
        mfxDesc.usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;
        _upscaledOutput = [_device newTextureWithDescriptor:mfxDesc];

        [self recreateMetalFXScaler];
    } else {
        _metalFXColorInput = nil;
        _upscaledOutput = nil;
#if HAS_METALFX
        _metalFXScaler = nil;
#endif
    }

    _frameIndex = 0;
}

- (void)updateUniforms {
    _uniformBufferOffset = alignedUniformsSize * _uniformBufferIndex;

    Uniforms *uniforms = (Uniforms *)((char *)_uniformBuffer.contents + _uniformBufferOffset);

    vector_float3 position, target, up;
    if (_useBistroPath) {
        position = _cameraPosition;
        target = _cameraTarget;
        up = simd_make_float3(0.0f, 1.0f, 0.0f);
    } else {
        position = _scene.cameraPosition;
        target = _scene.cameraTarget;
        up = _scene.cameraUp;
    }

    vector_float3 forward = vector_normalize(target - position);
    vector_float3 right = vector_normalize(vector_cross(forward, up));
    up = vector_normalize(vector_cross(right, forward));

    uniforms->camera.position = position;
    uniforms->camera.forward = forward;
    uniforms->camera.right = right;
    uniforms->camera.up = up;

    float fieldOfView = _useBistroPath ? (M_PI / 3.0f) : (45.0f * (M_PI / 180.0f));
    float aspectRatio = (float)_size.width / (float)_size.height;
    float imagePlaneHeight = tanf(fieldOfView / 2.0f);
    float imagePlaneWidth = aspectRatio * imagePlaneHeight;

    uniforms->camera.right *= imagePlaneWidth;
    uniforms->camera.up *= imagePlaneHeight;

    // Use internal resolution for RT dispatch when MetalFX is active
    bool useMetalFX = _renderOptions.enableMetalFXUpscaling && _metalFXSupported;
    CGSize renderSize = useMetalFX ? _internalSize : _displaySize;
    uniforms->width = (unsigned int)renderSize.width;
    uniforms->height = (unsigned int)renderSize.height;

    if (!_renderOptions.enableAccumulation)
        _frameIndex = 0;
    uniforms->frameIndex = _frameIndex++;

    // MetalFX jitter: deterministic Halton sequence for TAA
    uniforms->enableMetalFX = useMetalFX ? 1 : 0;
    if (useMetalFX) {
        // Halton sequence with base 2 and 3, mapped to [-0.5, 0.5] pixel range
        auto haltonSeq = [](int index, int base) -> float {
            float f = 1.0f, r = 0.0f;
            int i = index;
            while (i > 0) {
                f /= (float)base;
                r += f * (float)(i % base);
                i /= base;
            }
            return r;
        };
        _currentJitterX = haltonSeq(uniforms->frameIndex + 1, 2) - 0.5f;
        _currentJitterY = haltonSeq(uniforms->frameIndex + 1, 3) - 0.5f;
        uniforms->jitterX = _currentJitterX;
        uniforms->jitterY = _currentJitterY;
    } else {
        uniforms->jitterX = 0.0f;
        uniforms->jitterY = 0.0f;
    }

    uniforms->lightCount = _useBistroPath ? 0 : (unsigned int)_scene.lightCount;
    uniforms->enablePBR = _renderOptions.enablePBR ? 1 : 0;
    uniforms->debugMode = (unsigned int)_renderOptions.debugMode;
    uniforms->maxBounces = (unsigned int)_renderOptions.maxBounces;
    uniforms->emissiveIntensity = _renderOptions.emissiveIntensity;
    uniforms->emissiveLightCount = _useBistroPath ? (unsigned int)_gpuScene.emissiveLightCount : 0;
    uniforms->emissiveTotalWeight = _useBistroPath ? _gpuScene.emissiveTotalWeight : 0.0f;
    uniforms->enableShadows = _renderOptions.enableShadows ? 1 : 0;
    uniforms->enableReflections = _renderOptions.enableReflections ? 1 : 0;
    uniforms->denoiserMode = static_cast<unsigned int>(_renderOptions.denoiserMode);

    // Compute view-projection matrices for SVGF motion vectors
    {
        matrix_float4x4 viewMatrix = matrix4x4_look_at(position, target, up);
        matrix_float4x4 projMatrix = matrix4x4_perspective(fieldOfView, aspectRatio, 0.1f, 1000.0f);
        matrix_float4x4 vpMatrix = simd_mul(projMatrix, viewMatrix);

        uniforms->viewProjectionMatrix = vpMatrix;
        uniforms->inverseViewProjectionMatrix = matrix4x4_inverse(vpMatrix);

        if (_hasPrevViewProjectionMatrix) {
            uniforms->prevViewProjectionMatrix = _prevViewProjectionMatrix;
        } else {
            uniforms->prevViewProjectionMatrix = vpMatrix;
        }
        _prevViewProjectionMatrix = vpMatrix;
        _hasPrevViewProjectionMatrix = true;
    }

#if !TARGET_OS_IPHONE
    [_uniformBuffer didModifyRange:NSMakeRange(_uniformBufferOffset, alignedUniformsSize)];
#endif

    // Advance to the next slot in the uniform buffer.
    _uniformBufferIndex = (_uniformBufferIndex + 1) % maxFramesInFlight;
}

- (void)drawInMTKView:(MTKView *)view {
    // The sample uses the uniform buffer to stream uniform data to the GPU, so it
    // needs to wait until the GPU finishes processing the oldest GPU frame before
    // it can reuse that space in the buffer.
    dispatch_semaphore_wait(_sem, DISPATCH_TIME_FOREVER);

    // Create a command for the frame's commands.
    id <MTLCommandBuffer> commandBuffer = [_queue commandBuffer];

    __block dispatch_semaphore_t sem = _sem;

    // When the GPU finishes processing the command buffer for the frame, signal
    // the semaphore to make the space in uniform available for future frames.

    // Note: Completion handlers should be as fast as possible because the GPU
    // driver may have other work scheduled on the underlying dispatch queue.
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
        dispatch_semaphore_signal(sem);
    }];

    [self updateUniforms];

    NSUInteger width = (NSUInteger)_size.width;
    NSUInteger height = (NSUInteger)_size.height;

    // Launch a rectangular grid of threads on the GPU to perform ray tracing, with one thread per
    // pixel. The sample needs to align the number of threads to a multiple of the threadgroup
    // size, because earlier, when it created the pipeline objects, it declared that the pipeline
    // would always use a threadgroup size that's a multiple of the thread execution width
    // (SIMD group size). An 8x8 threadgroup is a safe threadgroup size and small enough to be
    // supported on most devices. A more advanced app would choose the threadgroup size dynamically.
    MTLSize threadsPerThreadgroup = MTLSizeMake(8, 8, 1);
    MTLSize threadgroups = MTLSizeMake((width  + threadsPerThreadgroup.width  - 1) / threadsPerThreadgroup.width,
                                       (height + threadsPerThreadgroup.height - 1) / threadsPerThreadgroup.height,
                                       1);

    // Create a compute encoder to encode GPU commands.
    id <MTLComputeCommandEncoder> computeEncoder = [commandBuffer computeCommandEncoder];

    if (_useBistroPath) {
        // ---- Bistro/GPUScene binding path ----
        [computeEncoder setBuffer:_uniformBuffer offset:_uniformBufferOffset atIndex:0];
        [computeEncoder setBuffer:_gpuScene.instanceBuffer offset:0 atIndex:2];
        [computeEncoder setBuffer:_gpuScene.materialBuffer offset:0 atIndex:6];
        [computeEncoder setBuffer:_textureArgBuffer offset:0 atIndex:7];
        if (_gpuScene.emissiveLightBuffer)
            [computeEncoder setBuffer:_gpuScene.emissiveLightBuffer offset:0 atIndex:8];

        [computeEncoder setAccelerationStructure:_gpuScene.instanceAccelerationStructure atBufferIndex:4];

        [computeEncoder setTexture:_randomTexture atIndex:0];
        [computeEncoder setTexture:_accumulationTargets[0] atIndex:1];
        [computeEncoder setTexture:_accumulationTargets[1] atIndex:2];
        [computeEncoder setTexture:_gbufferDepth atIndex:3];
        [computeEncoder setTexture:_gbufferNormal atIndex:4];
        [computeEncoder setTexture:_gbufferAlbedo atIndex:5];
        // Make all scene textures resident for bindless argument buffer access
        for (id<MTLTexture> tex in _gpuScene.textures)
            [computeEncoder useResource:tex usage:MTLResourceUsageRead];

        // Mark all BLAS as used
        for (id<MTLAccelerationStructure> blas in _gpuScene.primitiveAccelerationStructures)
            [computeEncoder useResource:blas usage:MTLResourceUsageRead];
    } else {
        // ---- Original Cornell box binding path ----
        [computeEncoder setBuffer:_uniformBuffer            offset:_uniformBufferOffset atIndex:0];
        if (!_usePerPrimitiveData) {
            [computeEncoder setBuffer:_resourceBuffer           offset:0                    atIndex:1];
        }
        [computeEncoder setBuffer:_instanceBuffer           offset:0                    atIndex:2];
        [computeEncoder setBuffer:_scene.lightBuffer        offset:0                    atIndex:3];

        [computeEncoder setAccelerationStructure:_instanceAccelerationStructure atBufferIndex:4];
        [computeEncoder setIntersectionFunctionTable:_intersectionFunctionTable atBufferIndex:5];

        [computeEncoder setTexture:_randomTexture atIndex:0];
        [computeEncoder setTexture:_accumulationTargets[0] atIndex:1];
        [computeEncoder setTexture:_accumulationTargets[1] atIndex:2];
        [computeEncoder setTexture:_gbufferDepth atIndex:3];
        [computeEncoder setTexture:_gbufferNormal atIndex:4];
        [computeEncoder setTexture:_gbufferAlbedo atIndex:5];

        for (Geometry *geometry in _scene.geometries)
            for (id <MTLResource> resource in geometry.resources)
                [computeEncoder useResource:resource usage:MTLResourceUsageRead];

        for (id <MTLAccelerationStructure> primitiveAccelerationStructure in _primitiveAccelerationStructures)
            [computeEncoder useResource:primitiveAccelerationStructure usage:MTLResourceUsageRead];
    }

    // Bind the compute pipeline state.
    [computeEncoder setComputePipelineState:_raytracingPipeline];

    // Dispatch the compute kernel to perform ray tracing.
    [computeEncoder dispatchThreadgroups:threadgroups threadsPerThreadgroup:threadsPerThreadgroup];

    [computeEncoder endEncoding];

    // Swap the source and destination accumulation targets for the next frame.
    std::swap(_accumulationTargets[0], _accumulationTargets[1]);

    // ---- Motion Vector Pass (needed for SVGF) ----
    {
        id<MTLComputeCommandEncoder> mvEncoder = [commandBuffer computeCommandEncoder];
        [mvEncoder setComputePipelineState:_motionVectorPipeline];
        [mvEncoder setBuffer:_uniformBuffer offset:_uniformBufferOffset atIndex:0];
        [mvEncoder setTexture:_gbufferDepth atIndex:0];
        [mvEncoder setTexture:_motionVectorTexture atIndex:1];
        [mvEncoder dispatchThreadgroups:threadgroups threadsPerThreadgroup:threadsPerThreadgroup];
        [mvEncoder endEncoding];
    }

    // The texture that the tone-map pass will read from (may be overridden by denoiser)
    id<MTLTexture> finalColorSource = _accumulationTargets[0];

    // ---- Debug: Motion Vector Visualization (mode 18) ----
    if (_renderOptions.debugMode == 18 && _debugMotionVectorPipeline) {
        id<MTLComputeCommandEncoder> dbgEncoder = [commandBuffer computeCommandEncoder];
        [dbgEncoder setComputePipelineState:_debugMotionVectorPipeline];
        [dbgEncoder setBuffer:_uniformBuffer offset:_uniformBufferOffset atIndex:0];
        [dbgEncoder setTexture:_motionVectorTexture atIndex:0];
        [dbgEncoder setTexture:_accumulationTargets[0] atIndex:1];
        [dbgEncoder dispatchThreadgroups:threadgroups threadsPerThreadgroup:threadsPerThreadgroup];
        [dbgEncoder endEncoding];
    }

    // ---- Debug: SVGF Variance Visualization (mode 19) ----
    if (_renderOptions.debugMode == 19 && _debugVariancePipeline) {
        id<MTLComputeCommandEncoder> dbgEncoder = [commandBuffer computeCommandEncoder];
        [dbgEncoder setComputePipelineState:_debugVariancePipeline];
        [dbgEncoder setBuffer:_uniformBuffer offset:_uniformBufferOffset atIndex:0];
        [dbgEncoder setTexture:_svgfVariance atIndex:0];
        [dbgEncoder setTexture:_accumulationTargets[0] atIndex:1];
        [dbgEncoder dispatchThreadgroups:threadgroups threadsPerThreadgroup:threadsPerThreadgroup];
        [dbgEncoder endEncoding];
    }

    // ---- SVGF Denoiser Pass ----
    if (_renderOptions.denoiserMode == DenoiserMode::SVGF && _svgfTemporalPipeline) {
        // On reset: the temporal kernel handles disocclusion gracefully —
        // mismatched prev G-buffer depth/normal causes fallback to current sample.
        _svgfNeedsClear = false;

        unsigned int cur = _svgfHistoryIndex;
        unsigned int prev = 1 - cur;

        // Step 1: Temporal accumulation
        {
            id<MTLComputeCommandEncoder> enc = [commandBuffer computeCommandEncoder];
            [enc setComputePipelineState:_svgfTemporalPipeline];
            [enc setBuffer:_uniformBuffer offset:_uniformBufferOffset atIndex:0];
            [enc setTexture:_accumulationTargets[0] atIndex:0]; // current 1-spp color
            [enc setTexture:_motionVectorTexture atIndex:1];
            [enc setTexture:_gbufferDepth atIndex:2];
            [enc setTexture:_gbufferNormal atIndex:3];
            [enc setTexture:_prevGbufferDepth atIndex:4];
            [enc setTexture:_prevGbufferNormal atIndex:5];
            [enc setTexture:_svgfColorHistory[prev] atIndex:6];
            [enc setTexture:_svgfMomentHistory[prev] atIndex:7];
            [enc setTexture:_svgfHistoryLength[prev] atIndex:8];
            [enc setTexture:_svgfColorHistory[cur] atIndex:9];
            [enc setTexture:_svgfMomentHistory[cur] atIndex:10];
            [enc setTexture:_svgfHistoryLength[cur] atIndex:11];
            [enc dispatchThreadgroups:threadgroups threadsPerThreadgroup:threadsPerThreadgroup];
            [enc endEncoding];
        }

        // Step 2: Variance estimation (if pipeline exists)
        if (_svgfVariancePipeline) {
            id<MTLComputeCommandEncoder> enc = [commandBuffer computeCommandEncoder];
            [enc setComputePipelineState:_svgfVariancePipeline];
            [enc setBuffer:_uniformBuffer offset:_uniformBufferOffset atIndex:0];
            [enc setTexture:_svgfMomentHistory[cur] atIndex:0];
            [enc setTexture:_svgfHistoryLength[cur] atIndex:1];
            [enc setTexture:_svgfVariance atIndex:2];
            [enc dispatchThreadgroups:threadgroups threadsPerThreadgroup:threadsPerThreadgroup];
            [enc endEncoding];
        }

        // Step 3: Variance-guided A-trous filter (if pipeline exists)
        if (_svgfAtrousPipeline) {
            id<MTLComputeCommandEncoder> enc = [commandBuffer computeCommandEncoder];
            [enc setComputePipelineState:_svgfAtrousPipeline];

            int iterations = _renderOptions.atrousIterations;
            for (int iter = 0; iter < iterations; iter++) {
                id<MTLTexture> input = (iter == 0) ? _svgfColorHistory[cur] : _denoiserPingPong[(iter - 1) % 2];
                id<MTLTexture> output = _denoiserPingPong[iter % 2];

                DenoiserParams params;
                params.stepSize = 1 << iter;
                params.sigmaColor = _renderOptions.denoiseSigmaColor;
                params.sigmaNormal = _renderOptions.denoiseSigmaNormal;
                params.sigmaDepth = _renderOptions.denoiseSigmaDepth;
                params.width = (unsigned int)width;
                params.height = (unsigned int)height;
                params.temporalBlend = 0.0f; // no temporal fade for SVGF
                params.isLastIteration = 0;

                [enc setBytes:&params length:sizeof(params) atIndex:0];
                [enc setTexture:input atIndex:0];
                [enc setTexture:output atIndex:1];
                [enc setTexture:_gbufferDepth atIndex:2];
                [enc setTexture:_gbufferNormal atIndex:3];
                [enc setTexture:_gbufferAlbedo atIndex:4];
                [enc setTexture:_svgfVariance atIndex:5];
                [enc dispatchThreadgroups:threadgroups threadsPerThreadgroup:threadsPerThreadgroup];
            }
            [enc endEncoding];

            finalColorSource = _denoiserPingPong[(iterations - 1) % 2];
        } else {
            // No spatial filter yet — show temporally accumulated result
            finalColorSource = _svgfColorHistory[cur];
        }

        // Flip history ping-pong
        _svgfHistoryIndex = 1 - _svgfHistoryIndex;
    }

    // ---- A-trous Denoiser Pass ----
    if (_renderOptions.denoiserMode == DenoiserMode::ATrous) {
        id<MTLComputeCommandEncoder> denoiseEncoder = [commandBuffer computeCommandEncoder];
        [denoiseEncoder setComputePipelineState:_atrousDenoiserPipeline];

        int iterations = _renderOptions.atrousIterations;

        // Compute temporal blend factor: fade denoiser out as samples accumulate
        // At frame 0: blend=0 (full denoise), fades toward 1 as frameIndex grows
        float temporalBlend = 1.0f - 1.0f / (1.0f + (float)_frameIndex * 0.15f);

        for (int iter = 0; iter < iterations; iter++) {
            // First iteration reads from accumulated result, subsequent iterations ping-pong
            id<MTLTexture> input = (iter == 0) ? _accumulationTargets[0] : _denoiserPingPong[(iter - 1) % 2];
            id<MTLTexture> output = _denoiserPingPong[iter % 2];

            DenoiserParams params;
            params.stepSize = 1 << iter; // 1, 2, 4, 8, 16
            params.sigmaColor = _renderOptions.denoiseSigmaColor;
            params.sigmaNormal = _renderOptions.denoiseSigmaNormal;
            params.sigmaDepth = _renderOptions.denoiseSigmaDepth;
            params.width = (unsigned int)width;
            params.height = (unsigned int)height;
            params.temporalBlend = temporalBlend;
            params.isLastIteration = (iter == iterations - 1) ? 1 : 0;

            [denoiseEncoder setBytes:&params length:sizeof(params) atIndex:0];
            [denoiseEncoder setTexture:input atIndex:0];
            [denoiseEncoder setTexture:output atIndex:1];
            [denoiseEncoder setTexture:_gbufferDepth atIndex:2];
            [denoiseEncoder setTexture:_gbufferNormal atIndex:3];
            [denoiseEncoder setTexture:_gbufferAlbedo atIndex:4];

            [denoiseEncoder dispatchThreadgroups:threadgroups threadsPerThreadgroup:threadsPerThreadgroup];
        }

        [denoiseEncoder endEncoding];

        // The final denoised result is in the last-written ping-pong texture
        finalColorSource = _denoiserPingPong[(iterations - 1) % 2];
    }

    // ---- MetalFX Temporal Upscaling ----
#if HAS_METALFX
    if (@available(macOS 13.0, *)) {
        bool useMetalFX = _renderOptions.enableMetalFXUpscaling && _metalFXSupported && _metalFXScaler;
        if (useMetalFX) {
            // Convert finalColorSource (RGBA32Float) → _metalFXColorInput (RGBA16Float)
            {
                id<MTLComputeCommandEncoder> enc = [commandBuffer computeCommandEncoder];
                [enc setComputePipelineState:_formatConvertPipeline];
                [enc setTexture:finalColorSource atIndex:0];
                [enc setTexture:_metalFXColorInput atIndex:1];
                NSUInteger iw = (NSUInteger)_internalSize.width;
                NSUInteger ih = (NSUInteger)_internalSize.height;
                MTLSize tg = MTLSizeMake(8, 8, 1);
                MTLSize grid = MTLSizeMake((iw + 7) / 8, (ih + 7) / 8, 1);
                [enc dispatchThreadgroups:grid threadsPerThreadgroup:tg];
                [enc endEncoding];
            }

            // Configure and encode the MetalFX temporal scaler
            _metalFXScaler.colorTexture = _metalFXColorInput;
            _metalFXScaler.depthTexture = _gbufferDepth;
            _metalFXScaler.motionTexture = _motionVectorTexture;
            _metalFXScaler.outputTexture = _upscaledOutput;
            _metalFXScaler.jitterOffsetX = _currentJitterX;
            _metalFXScaler.jitterOffsetY = _currentJitterY;
            _metalFXScaler.reset = (_frameIndex <= 1);

            [_metalFXScaler encodeToCommandBuffer:commandBuffer];

            // Tone-map reads from upscaled output
            finalColorSource = _upscaledOutput;
        }
    }
#endif

    if (view.currentDrawable) {
        MTLRenderPassDescriptor* renderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];

        renderPassDescriptor.colorAttachments[0].texture    = view.currentDrawable.texture;
        renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.0f, 0.0f, 0.0f, 1.0f);

        id <MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];

        [renderEncoder setRenderPipelineState:_copyPipeline];

        [renderEncoder setFragmentTexture:finalColorSource atIndex:0];

        float exposure = _renderOptions.exposureAdjust;
        [renderEncoder setFragmentBytes:&exposure length:sizeof(float) atIndex:0];

        // Draw a quad which fills the screen.
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];

        [renderEncoder endEncoding];

        // Present the drawable to the screen.
        [commandBuffer presentDrawable:view.currentDrawable];
    }

    // Copy current G-buffer to previous frame storage (for SVGF temporal validation next frame)
    {
        id<MTLBlitCommandEncoder> blit = [commandBuffer blitCommandEncoder];
        [blit copyFromTexture:_gbufferDepth toTexture:_prevGbufferDepth];
        [blit copyFromTexture:_gbufferNormal toTexture:_prevGbufferNormal];
        [blit endEncoding];
    }

    // Finally, commit the command buffer so that the GPU can start executing.
    [commandBuffer commit];
}

@end
