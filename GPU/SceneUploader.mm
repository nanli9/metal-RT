#import "SceneUploader.h"
#import "GPUScene+Private.h"
#import "SceneAsset.h"
#import "MaterialAsset.h"
#import "TextureAsset.h"
#import "TextureCache.h"
#import "MeshAsset.h"
#import "ShaderTypes.h"

@implementation SceneUploader

+ (void)uploadScene:(SceneAsset *)sceneAsset
         toGPUScene:(GPUScene *)gpuScene
             device:(id<MTLDevice>)device
{
    auto &meshes = sceneAsset.meshes;
    auto &instances = sceneAsset.instances;
    NSArray<MaterialAsset *> *materials = sceneAsset.materials;

    // ---- Compute total sizes ----
    uint32_t totalVertices = 0;
    uint32_t totalIndices = 0;
    uint32_t totalTriangles = 0;

    std::vector<MeshGPUInfo> meshInfos;
    meshInfos.reserve(meshes.size());

    for (auto &mesh : meshes) {
        MeshGPUInfo info;
        info.vertexOffset = totalVertices;
        info.vertexCount = mesh.vertexCount();
        info.indexOffset = totalIndices;
        info.indexCount = (uint32_t)mesh.indices.size();
        info.triangleOffset = totalTriangles;
        info.materialIndex = mesh.materialIndex;
        meshInfos.push_back(info);

        totalVertices += mesh.vertexCount();
        totalIndices += (uint32_t)mesh.indices.size();
        totalTriangles += mesh.triangleCount();
    }

    NSLog(@"SceneUploader: uploading %u vertices, %u indices, %u triangles",
          totalVertices, totalIndices, totalTriangles);

    // ---- Create vertex/index buffers ----
    MTLResourceOptions bufferOpts = MTLResourceStorageModeShared;

    id<MTLBuffer> positionBuf = [device newBufferWithLength:totalVertices * sizeof(simd_float3) options:bufferOpts];
    id<MTLBuffer> normalBuf   = [device newBufferWithLength:totalVertices * sizeof(simd_float3) options:bufferOpts];
    id<MTLBuffer> uvBuf       = [device newBufferWithLength:totalVertices * sizeof(simd_float2) options:bufferOpts];
    id<MTLBuffer> tangentBuf  = [device newBufferWithLength:totalVertices * sizeof(simd_float4) options:bufferOpts];
    id<MTLBuffer> indexBuf    = [device newBufferWithLength:totalIndices * sizeof(uint32_t) options:bufferOpts];

    positionBuf.label = @"Vertex Positions";
    normalBuf.label   = @"Vertex Normals";
    uvBuf.label       = @"Vertex UVs";
    tangentBuf.label  = @"Vertex Tangents";
    indexBuf.label    = @"Indices";

    simd_float3 *posPtr = (simd_float3 *)positionBuf.contents;
    simd_float3 *nrmPtr = (simd_float3 *)normalBuf.contents;
    simd_float2 *uvPtr  = (simd_float2 *)uvBuf.contents;
    simd_float4 *tanPtr = (simd_float4 *)tangentBuf.contents;
    uint32_t    *idxPtr = (uint32_t *)indexBuf.contents;

    for (size_t mi = 0; mi < meshes.size(); mi++) {
        auto &mesh = meshes[mi];
        auto &info = meshInfos[mi];

        memcpy(posPtr + info.vertexOffset, mesh.positions.data(), mesh.positions.size() * sizeof(simd_float3));
        memcpy(nrmPtr + info.vertexOffset, mesh.normals.data(),   mesh.normals.size() * sizeof(simd_float3));
        memcpy(uvPtr  + info.vertexOffset, mesh.uvs.data(),       mesh.uvs.size() * sizeof(simd_float2));
        memcpy(tanPtr + info.vertexOffset, mesh.tangents.data(),  mesh.tangents.size() * sizeof(simd_float4));

        // Offset indices by the mesh's vertex offset
        for (size_t i = 0; i < mesh.indices.size(); i++) {
            idxPtr[info.indexOffset + i] = mesh.indices[i] + info.vertexOffset;
        }
    }

    // ---- Create per-primitive data buffer ----
    // GPUTriangleData: 3 normals + 3 UVs + 3 tangents + material index
    id<MTLBuffer> perPrimBuf = [device newBufferWithLength:totalTriangles * sizeof(GPUTriangleData) options:bufferOpts];
    perPrimBuf.label = @"Per-Primitive Data";
    GPUTriangleData *primPtr = (GPUTriangleData *)perPrimBuf.contents;

    for (size_t mi = 0; mi < meshes.size(); mi++) {
        auto &mesh = meshes[mi];
        auto &info = meshInfos[mi];

        for (uint32_t ti = 0; ti < mesh.triangleCount(); ti++) {
            uint32_t baseIdx = ti * 3;
            GPUTriangleData &tri = primPtr[info.triangleOffset + ti];

            for (int v = 0; v < 3; v++) {
                uint32_t vi = mesh.indices[baseIdx + v];
                tri.normals[v][0] = mesh.normals[vi].x;
                tri.normals[v][1] = mesh.normals[vi].y;
                tri.normals[v][2] = mesh.normals[vi].z;
                tri.uvs[v][0] = mesh.uvs[vi].x;
                tri.uvs[v][1] = mesh.uvs[vi].y;
                tri.tangents[v][0] = mesh.tangents[vi].x;
                tri.tangents[v][1] = mesh.tangents[vi].y;
                tri.tangents[v][2] = mesh.tangents[vi].z;
                tri.tangentSign[v] = mesh.tangents[vi].w;
            }
            tri.materialIndex = info.materialIndex;
        }
    }

    // ---- Create material buffer ----
    id<MTLBuffer> materialBuf = [device newBufferWithLength:materials.count * sizeof(GPUMaterial) options:bufferOpts];
    materialBuf.label = @"Materials";
    GPUMaterial *matPtr = (GPUMaterial *)materialBuf.contents;

    // Collect all unique textures for the texture array
    NSMutableArray<id<MTLTexture>> *textureArray = [NSMutableArray new];
    NSMutableDictionary<NSValue *, NSNumber *> *textureIndexMap = [NSMutableDictionary new];

    auto getTextureIndex = [&](TextureAsset *texAsset) -> uint32_t {
        if (!texAsset) return UINT32_MAX;
        NSValue *key = [NSValue valueWithPointer:(__bridge const void *)texAsset.texture];
        NSNumber *existing = textureIndexMap[key];
        if (existing) return existing.unsignedIntValue;

        uint32_t idx = (uint32_t)textureArray.count;
        [textureArray addObject:texAsset.texture];
        textureIndexMap[key] = @(idx);
        return idx;
    };

    for (NSUInteger i = 0; i < materials.count; i++) {
        MaterialAsset *mat = materials[i];
        GPUMaterial &gpu = matPtr[i];

        gpu.baseColorTextureIndex  = getTextureIndex(mat.baseColorTexture);
        gpu.normalTextureIndex     = getTextureIndex(mat.normalTexture);
        gpu.specularTextureIndex   = getTextureIndex(mat.specularTexture);
        gpu.emissiveTextureIndex   = getTextureIndex(mat.emissiveTexture);

        gpu.baseColorFactor[0] = mat.baseColorFactor.x;
        gpu.baseColorFactor[1] = mat.baseColorFactor.y;
        gpu.baseColorFactor[2] = mat.baseColorFactor.z;
        gpu.roughnessFactor = mat.roughnessFactor;
        gpu.metallicFactor  = mat.metallicFactor;
        gpu.emissiveFactor[0] = mat.emissiveFactor.x;
        gpu.emissiveFactor[1] = mat.emissiveFactor.y;
        gpu.emissiveFactor[2] = mat.emissiveFactor.z;
        gpu.opacity         = mat.opacity;
    }

    NSLog(@"SceneUploader: %lu unique textures collected for GPU", (unsigned long)textureArray.count);

    // ---- Create instance buffer ----
    id<MTLBuffer> instanceBuf = [device newBufferWithLength:instances.size() * sizeof(MTLAccelerationStructureInstanceDescriptor)
                                                   options:bufferOpts];
    instanceBuf.label = @"Instance Descriptors";

    // Instance descriptors will be filled by AccelerationStructureBuilder

    // ---- Store everything on GPUScene ----
    [gpuScene setVertexPositionBuffer:positionBuf];
    [gpuScene setVertexNormalBuffer:normalBuf];
    [gpuScene setVertexUVBuffer:uvBuf];
    [gpuScene setVertexTangentBuffer:tangentBuf];
    [gpuScene setIndexBuffer:indexBuf];
    [gpuScene setPerPrimitiveDataBuffer:perPrimBuf];
    [gpuScene setMaterialBuffer:materialBuf];
    [gpuScene setMaterialCount:materials.count];
    [gpuScene setTextures:textureArray];
    [gpuScene setInstanceBuffer:instanceBuf];
    [gpuScene setInstanceCount:instances.size()];
    [gpuScene setMeshInfos:std::move(meshInfos)];

    NSLog(@"SceneUploader: upload complete");
}

@end
