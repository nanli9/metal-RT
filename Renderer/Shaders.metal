/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The Metal shaders used for this sample.
*/
#include "ShaderTypes.h"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

using namespace raytracing;

constant unsigned int resourcesStride   [[function_constant(0)]];
constant bool useIntersectionFunctions  [[function_constant(1)]];
constant bool usePerPrimitiveData       [[function_constant(2)]];
constant bool bistroMode                [[function_constant(3)]];
constant bool useResourcesBuffer = !usePerPrimitiveData;

constant unsigned int primes[] = {
    2,   3,  5,  7,
    11, 13, 17, 19,
    23, 29, 31, 37,
    41, 43, 47, 53,
    59, 61, 67, 71,
    73, 79, 83, 89
};

// Returns the i'th element of the Halton sequence using the d'th prime number as a
// base. The Halton sequence is a low discrepency sequence: the values appear
// random, but are more evenly distributed than a purely random sequence. Each random
// value used to render the image uses a different independent dimension, `d`,
// and each sample (frame) uses a different index `i`. To decorrelate each pixel,
// you can apply a random offset to `i`.
float halton(unsigned int i, unsigned int d) {
    unsigned int b = primes[d];

    float f = 1.0f;
    float invB = 1.0f / b;

    float r = 0;

    while (i > 0) {
        f = f * invB;
        r = r + f * (i % b);
        i = i / b;
    }

    return r;
}

// Interpolates the vertex attribute of an arbitrary type across the surface of a triangle
// given the barycentric coordinates and triangle index in an intersection structure.
template<typename T, typename IndexType>
inline T interpolateVertexAttribute(device T *attributes,
                                    IndexType i0,
                                    IndexType i1,
                                    IndexType i2,
                                    float2 uv) {
    // Look up value for each vertex.
    const T T0 = attributes[i0];
    const T T1 = attributes[i1];
    const T T2 = attributes[i2];

    // Compute the sum of the vertex attributes weighted by the barycentric coordinates.
    // The barycentric coordinates sum to one.
    return (1.0f - uv.x - uv.y) * T0 + uv.x * T1 + uv.y * T2;
}

template<typename T>
inline T interpolateVertexAttribute(thread T *attributes, float2 uv) {
    // Look up the value for each vertex.
    const T T0 = attributes[0];
    const T T1 = attributes[1];
    const T T2 = attributes[2];

    // Compute the sum of the vertex attributes weighted by the barycentric coordinates.
    // The barycentric coordinates sum to one.
    return (1.0f - uv.x - uv.y) * T0 + uv.x * T1 + uv.y * T2;
}

// Uses the inversion method to map two uniformly random numbers to a 3D
// unit hemisphere, where the probability of a given sample is proportional to the cosine
// of the angle between the sample direction and the "up" direction (0, 1, 0).
inline float3 sampleCosineWeightedHemisphere(float2 u) {
    float phi = 2.0f * M_PI_F * u.x;

    float cos_phi;
    float sin_phi = sincos(phi, cos_phi);

    float cos_theta = sqrt(u.y);
    float sin_theta = sqrt(1.0f - cos_theta * cos_theta);

    return float3(sin_theta * cos_phi, cos_theta, sin_theta * sin_phi);
}

// Maps two uniformly random numbers to the surface of a 2D area light
// source and returns the direction to this point, the amount of light that travels
// between the intersection point and the sample point on the light source, as well
// as the distance between these two points.

inline void sampleAreaLight(constant AreaLight & light,
                            float2 u,
                            float3 position,
                            thread float3 & lightDirection,
                            thread float3 & lightColor,
                            thread float & lightDistance)
{
    // Map to -1..1
    u = u * 2.0f - 1.0f;

    // Transform into the light's coordinate system.
    float3 samplePosition = light.position +
                            light.right * u.x +
                            light.up * u.y;

    // Compute the vector from sample point on  the light source to intersection point.
    lightDirection = samplePosition - position;

    lightDistance = length(lightDirection);

    float inverseLightDistance = 1.0f / max(lightDistance, 1e-3f);

    // Normalize the light direction.
    lightDirection *= inverseLightDistance;

    // Start with the light's color.
    lightColor = light.color;

    // Light falls off with the inverse square of the distance to the intersection point.
    lightColor *= (inverseLightDistance * inverseLightDistance);

    // Light also falls off with the cosine of the angle between the intersection point
    // and the light source.
    lightColor *= saturate(dot(-lightDirection, light.forward));
}

// Aligns a direction on the unit hemisphere such that the hemisphere's "up" direction
// (0, 1, 0) maps to the given surface normal direction.
inline float3 alignHemisphereWithNormal(float3 sample, float3 normal) {
    // Set the "up" vector to the normal
    float3 up = normal;

    // Find an arbitrary direction perpendicular to the normal, which becomes the
    // "right" vector.
    float3 right = normalize(cross(normal, float3(0.0072f, 1.0f, 0.0034f)));

    // Find a third vector perpendicular to the previous two, which becomes the
    // "forward" vector.
    float3 forward = cross(right, up);

    // Map the direction on the unit hemisphere to the coordinate system aligned
    // with the normal.
    return sample.x * right + sample.y * up + sample.z * forward;
}

// ---- Argument buffer for bindless texture access (Metal 3) ----

struct SceneTextureArgBuffer {
    array<texture2d<float>, 512> textures [[id(0)]];
};

// ---- PBR helper functions ----

constexpr sampler texSampler(filter::linear, address::repeat);

inline float3 sampleTexture(device SceneTextureArgBuffer &argBuf, uint texIdx, float2 uv) {
    if (texIdx == 0xFFFFFFFF) return float3(1.0f);
    return argBuf.textures[texIdx].sample(texSampler, uv).rgb;
}

inline float4 sampleTexture4(device SceneTextureArgBuffer &argBuf, uint texIdx, float2 uv) {
    if (texIdx == 0xFFFFFFFF) return float4(1.0f);
    return argBuf.textures[texIdx].sample(texSampler, uv);
}

// GGX/Trowbridge-Reitz normal distribution function
inline float distributionGGX(float NdotH, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    float denom = NdotH * NdotH * (a2 - 1.0f) + 1.0f;
    return a2 / (M_PI_F * denom * denom + 1e-7f);
}

// Schlick geometry function
inline float geometrySchlickGGX(float NdotV, float roughness) {
    float r = roughness + 1.0f;
    float k = (r * r) / 8.0f;
    return NdotV / (NdotV * (1.0f - k) + k);
}

inline float geometrySmith(float NdotV, float NdotL, float roughness) {
    return geometrySchlickGGX(NdotV, roughness) * geometrySchlickGGX(NdotL, roughness);
}

// Fresnel-Schlick approximation
inline float3 fresnelSchlick(float cosTheta, float3 F0) {
    return F0 + (1.0f - F0) * pow(saturate(1.0f - cosTheta), 5.0f);
}

// Evaluate PBR direct lighting for a single light direction
inline float3 evaluatePBR(float3 N, float3 V, float3 L,
                          float3 albedo, float metallic, float roughness,
                          float3 lightColor) {
    float3 H = normalize(V + L);

    float NdotL = saturate(dot(N, L));
    float NdotV = saturate(dot(N, V));
    float NdotH = saturate(dot(N, H));
    float HdotV = saturate(dot(H, V));

    if (NdotL <= 0.0f) return float3(0.0f);

    float3 F0 = mix(float3(0.04f), albedo, metallic);

    float D = distributionGGX(NdotH, roughness);
    float G = geometrySmith(NdotV, NdotL, roughness);
    float3 F = fresnelSchlick(HdotV, F0);

    // Specular BRDF
    float3 specular = (D * G * F) / (4.0f * NdotV * NdotL + 1e-4f);

    // Diffuse: metals have no diffuse
    float3 kD = (1.0f - F) * (1.0f - metallic);
    float3 diffuse = kD * albedo / M_PI_F;

    return (diffuse + specular) * lightColor * NdotL;
}

// Apply normal map using TBN matrix
inline float3 applyNormalMap(float3 normalMapSample, float3 N, float3 T, float tangentSign) {
    // Normal map is in tangent space, convert from [0,1] to [-1,1]
    float3 tangentNormal = normalMapSample * 2.0f - 1.0f;

    // Build TBN matrix
    float3 B = cross(N, T) * tangentSign;
    float3x3 TBN = float3x3(T, B, N);

    return normalize(TBN * tangentNormal);
}

// Return the type for a bounding box intersection function.
struct BoundingBoxIntersection {
    bool accept    [[accept_intersection]]; // Whether to accept or reject the intersection.
    float distance [[distance]];            // Distance from the ray origin to the intersection point.
};

// Resources for a piece of triangle geometry.
struct TriangleResources {
    device uint16_t *indices;
    device float3 *vertexNormals;
    device float3 *vertexColors;
};

// Resources for a piece of sphere geometry.
struct SphereResources {
    device Sphere *spheres;
};

/*
 Custom sphere intersection function. The [[intersection]] keyword marks this as an intersection
 function. The [[bounding_box]] keyword means that this intersection function handles intersecting rays
 with bounding box primitives. To create sphere primitives, the sample creates bounding boxes that
 enclose the sphere primitives.

 The [[triangle_data]] and [[instancing]] keywords indicate that the intersector that calls this
 intersection function returns barycentric coordinates for triangle intersections and traverses
 an instance acceleration structure. These keywords must match between the intersection functions,
 intersection function table, intersector, and intersection result to ensure that Metal propagates
 data correctly between stages. Using fewer tags when possible may result in better performance,
 as Metal may need to store less data and pass less data between stages. For example, if you do not
 need barycentric coordinates, omitting [[triangle_data]] means Metal can avoid computing and storing
 them.

 The arguments to the intersection function contain information about the ray, primitive to be
 tested, and so on. The ray intersector provides this datas when it calls the intersection function.
 Metal provides other built-in arguments, but this sample doesn't use them.
 */
[[intersection(bounding_box, triangle_data, instancing)]]
BoundingBoxIntersection sphereIntersectionFunction(// Ray parameters passed to the ray intersector below
                                                   float3 origin                        [[origin]],
                                                   float3 direction                     [[direction]],
                                                   float minDistance                    [[min_distance]],
                                                   float maxDistance                    [[max_distance]],
                                                   // Information about the primitive.
                                                   unsigned int primitiveIndex          [[primitive_id]],
                                                   unsigned int geometryIndex           [[geometry_intersection_function_table_offset]],
                                                   // Custom resources bound to the intersection function table.
                                                   device void *resources               [[buffer(0), function_constant(useResourcesBuffer)]]
#if SUPPORTS_METAL_3
                                                   ,const device void* perPrimitiveData [[primitive_data]]
#endif
                                                   )
{
    Sphere sphere;
#if SUPPORTS_METAL_3
    // Look up the resources for this piece of sphere geometry.
    if (usePerPrimitiveData) {
        // Per-primitive data points to data from the specified buffer as was configured in the MTLAccelerationStructureBoundingBoxGeometryDescriptor.
        sphere = *(const device Sphere*)perPrimitiveData;
    } else
#endif
    {
        device SphereResources& sphereResources = *(device SphereResources *)((device char *)resources + resourcesStride * geometryIndex);
        // Get the actual sphere enclosed in this bounding box.
        sphere = sphereResources.spheres[primitiveIndex];
    }

    // Check for intersection between the ray and sphere mathematically.
    float3 oc = origin - sphere.origin;

    float a = dot(direction, direction);
    float b = 2 * dot(oc, direction);
    float c = dot(oc, oc) - sphere.radiusSquared;

    float disc = b * b - 4 * a * c;

    BoundingBoxIntersection ret;

    if (disc <= 0.0f) {
        // If the ray missed the sphere, return false.
        ret.accept = false;
    }
    else {
        // Otherwise, compute the intersection distance.
        ret.distance = (-b - sqrt(disc)) / (2 * a);

        // The intersection function must also check whether the intersection distance is
        // within the acceptable range. Intersection functions do not run in any particular order,
        // so the maximum distance may be different from the one passed into the ray intersector.
        ret.accept = ret.distance >= minDistance && ret.distance <= maxDistance;
    }

    return ret;
}

__attribute__((always_inline))
float3 transformPoint(float3 p, float4x4 transform) {
    return (transform * float4(p.x, p.y, p.z, 1.0f)).xyz;
}

__attribute__((always_inline))
float3 transformDirection(float3 p, float4x4 transform) {
    return (transform * float4(p.x, p.y, p.z, 0.0f)).xyz;
}

// Main ray tracing kernel.
kernel void raytracingKernel(
     uint2                                                  tid                       [[thread_position_in_grid]],
     constant Uniforms &                                    uniforms                  [[buffer(0)]],
     texture2d<unsigned int>                                randomTex                 [[texture(0)]],
     texture2d<float>                                       prevTex                   [[texture(1)]],
     texture2d<float, access::write>                        dstTex                    [[texture(2)]],
     device void                                           *resources                 [[buffer(1), function_constant(useResourcesBuffer)]],
     constant MTLAccelerationStructureInstanceDescriptor   *instances                 [[buffer(2)]],
     constant AreaLight                                    *areaLights                [[buffer(3)]],
     instance_acceleration_structure                        accelerationStructure     [[buffer(4)]],
     intersection_function_table<triangle_data, instancing> intersectionFunctionTable [[buffer(5)]],
     constant GPUMaterial                                  *materials                 [[buffer(6), function_constant(bistroMode)]],
     device SceneTextureArgBuffer                          &sceneTexArgBuf            [[buffer(7), function_constant(bistroMode)]]
)
{
    // The sample aligns the thread count to the threadgroup size, which means the thread count
    // may be different than the bounds of the texture. Test to make sure this thread
    // is referencing a pixel within the bounds of the texture.
    if (tid.x < uniforms.width && tid.y < uniforms.height) {
        // The ray to cast.
        ray ray;

        // Pixel coordinates for this thread.
        float2 pixel = (float2)tid;

        // Apply a random offset to the random number index to decorrelate pixels.
        unsigned int offset = randomTex.read(tid).x;

        // Add a random offset to the pixel coordinates for antialiasing.
        float2 r = float2(halton(offset + uniforms.frameIndex, 0),
                          halton(offset + uniforms.frameIndex, 1));

        pixel += r;

        // Map pixel coordinates to -1..1.
        float2 uv = (float2)pixel / float2(uniforms.width, uniforms.height);
        uv = uv * 2.0f - 1.0f;

        constant Camera & camera = uniforms.camera;

        // Rays start at the camera position.
        ray.origin = camera.position;

        // Map normalized pixel coordinates into camera's coordinate system.
        ray.direction = normalize(uv.x * camera.right +
                                  uv.y * camera.up +
                                  camera.forward);

        // Don't limit intersection distance.
        ray.max_distance = INFINITY;

        // Start with a fully white color. The kernel scales the light each time the
        // ray bounces off of a surface, based on how much of each light component
        // the surface absorbs.
        float3 color = float3(1.0f, 1.0f, 1.0f);

        float3 accumulatedColor = float3(0.0f, 0.0f, 0.0f);

        // Debug data captured from first bounce
        float3 dbgSurfaceColor = 0.0f;
        float3 dbgWorldNormal = 0.0f;
        float3 dbgBarycentrics = 0.0f;
        uint dbgPrimitiveId = 0;
        uint dbgMaterialId = 0;
        uint dbgInstanceId = 0;
        float dbgNdotL = 0.0f;
        float dbgShadow = 1.0f;
        bool dbgHit = false;
        float2 dbgUV = 0.0f;
        float3 dbgBaseTexSample = 0.0f; // raw texture sample at UV
        float dbgAO = 1.0f;
        uint dbgBaseTexIdx = 0xFFFFFFFF;

        // Create an intersector to test for intersection between the ray and the geometry in the scene.
        intersector<triangle_data, instancing> i;

        // If the sample isn't using intersection functions, provide some hints to Metal for
        // better performance.
        if (!useIntersectionFunctions) {
            i.assume_geometry_type(geometry_type::triangle);
            i.force_opacity(forced_opacity::opaque);
        }

        typename intersector<triangle_data, instancing>::result_type intersection;

        // Simulate up to three ray bounces. Each bounce propagates light backward along the
        // ray's path toward the camera.
        for (int bounce = 0; bounce < 3; bounce++) {
            // Get the closest intersection, not the first intersection. This is the default, but
            // the sample adjusts this property below when it casts shadow rays.
            i.accept_any_intersection(false);

            // Check for intersection between the ray and the acceleration structure. If the sample
            // isn't using intersection functions, it doesn't need to include one.
            if (useIntersectionFunctions)
                intersection = i.intersect(ray, accelerationStructure, bounce == 0 ? RAY_MASK_PRIMARY : RAY_MASK_SECONDARY, intersectionFunctionTable);
            else
                intersection = i.intersect(ray, accelerationStructure, bounce == 0 ? RAY_MASK_PRIMARY : RAY_MASK_SECONDARY);

            // Stop if the ray didn't hit anything and has bounced out of the scene.
            if (intersection.type == intersection_type::none) {
                if (bistroMode) {
                    // Simple procedural sky gradient
                    float3 dir = normalize(ray.direction);
                    float t = saturate(dir.y * 0.5f + 0.5f);
                    float3 skyColor = mix(float3(0.8f, 0.85f, 0.9f),  // horizon
                                          float3(0.4f, 0.6f, 1.0f),   // zenith
                                          t);
                    accumulatedColor += skyColor * color * 0.5f;
                }
                break;
            }

            unsigned int instanceIndex = intersection.instance_id;

            // Look up the mask for this instance, which indicates what type of geometry the ray hit.
            unsigned int mask = instances[instanceIndex].mask;

            // If the ray hit a light source, set the color to white, and stop immediately.
            if (mask == GEOMETRY_MASK_LIGHT) {
                accumulatedColor = float3(1.0f, 1.0f, 1.0f);
                break;
            }

            // The ray hit something. Look up the transformation matrix for this instance.
            float4x4 objectToWorldSpaceTransform(1.0f);

            for (int column = 0; column < 4; column++)
                for (int row = 0; row < 3; row++)
                    objectToWorldSpaceTransform[column][row] = instances[instanceIndex].transformationMatrix[column][row];

            // Compute the intersection point in world space.
            float3 worldSpaceIntersectionPoint = ray.origin + ray.direction * intersection.distance;

            unsigned primitiveIndex = intersection.primitive_id;
            unsigned int geometryIndex = instances[instanceIndex].accelerationStructureIndex;
            float2 barycentric_coords = intersection.triangle_barycentric_coord;

            float3 worldSpaceSurfaceNormal = 0.0f;
            float3 surfaceColor = 0.0f;
            float bistroRoughness = 0.5f;
            float bistroMetallic = 0.0f;

            if (mask & GEOMETRY_MASK_TRIANGLE) {
                float3 objectSpaceSurfaceNormal;

#if SUPPORTS_METAL_3
                if (bistroMode && usePerPrimitiveData) {
                    // Bistro path: read GPUTriangleData from per-primitive data
                    const device GPUTriangleData &tri = *(const device GPUTriangleData*)intersection.primitive_data;
                    float w0 = 1.0f - barycentric_coords.x - barycentric_coords.y;

                    // Interpolate normals
                    float3 n0 = float3(tri.normals[0][0], tri.normals[0][1], tri.normals[0][2]);
                    float3 n1 = float3(tri.normals[1][0], tri.normals[1][1], tri.normals[1][2]);
                    float3 n2 = float3(tri.normals[2][0], tri.normals[2][1], tri.normals[2][2]);
                    objectSpaceSurfaceNormal = w0 * n0 + barycentric_coords.x * n1 + barycentric_coords.y * n2;

                    // Interpolate UVs
                    float2 uv0 = float2(tri.uvs[0][0], tri.uvs[0][1]);
                    float2 uv1 = float2(tri.uvs[1][0], tri.uvs[1][1]);
                    float2 uv2 = float2(tri.uvs[2][0], tri.uvs[2][1]);
                    float2 uv = w0 * uv0 + barycentric_coords.x * uv1 + barycentric_coords.y * uv2;

                    // Interpolate tangents
                    float3 t0 = float3(tri.tangents[0][0], tri.tangents[0][1], tri.tangents[0][2]);
                    float3 t1 = float3(tri.tangents[1][0], tri.tangents[1][1], tri.tangents[1][2]);
                    float3 t2 = float3(tri.tangents[2][0], tri.tangents[2][1], tri.tangents[2][2]);
                    float3 objectTangent = normalize(w0 * t0 + barycentric_coords.x * t1 + barycentric_coords.y * t2);
                    float tangentSign = tri.tangentSign[0]; // same for all verts of triangle

                    // Look up material
                    constant GPUMaterial &mat = materials[tri.materialIndex];

                    if (uniforms.enablePBR) {
                        // Full PBR path: sample all textures
                        float3 baseColor = float3(mat.baseColorFactor[0], mat.baseColorFactor[1], mat.baseColorFactor[2]);
                        baseColor *= sampleTexture(sceneTexArgBuf, mat.baseColorTextureIndex, uv);

                        float3 worldNormal = normalize(transformDirection(objectSpaceSurfaceNormal, objectToWorldSpaceTransform));
                        float3 worldTangent = normalize(transformDirection(objectTangent, objectToWorldSpaceTransform));

                        // Apply normal map (only if tangent is valid)
                        if (mat.normalTextureIndex != 0xFFFFFFFF && length_squared(worldTangent) > 0.001f) {
                            float3 normalMapVal = sampleTexture(sceneTexArgBuf, mat.normalTextureIndex, uv);
                            worldNormal = applyNormalMap(normalMapVal, worldNormal, worldTangent, tangentSign);
                        }

                        // Read roughness/metalness from specular texture
                        // Bistro packing: R=unused(0), G=Roughness, B=Metalness
                        float roughness = mat.roughnessFactor;
                        float metallic = mat.metallicFactor;
                        if (mat.specularTextureIndex != 0xFFFFFFFF) {
                            float3 spec = sampleTexture(sceneTexArgBuf, mat.specularTextureIndex, uv);
                            roughness = spec.y;
                            metallic = spec.z;
                        }

                        worldSpaceSurfaceNormal = worldNormal;
                        surfaceColor = baseColor;
                        bistroRoughness = roughness;
                        bistroMetallic = metallic;

                        // Capture PBR debug data
                        if (bounce == 0) {
                            dbgUV = uv;
                            dbgBaseTexSample = sampleTexture(sceneTexArgBuf, mat.baseColorTextureIndex, uv);
                            dbgAO = 1.0f; // AO no longer read from specular texture
                            dbgBaseTexIdx = mat.baseColorTextureIndex;
                        }
                    } else {
                        // Simple flat shading (Phase 4 style): material base color only
                        surfaceColor = float3(mat.baseColorFactor[0], mat.baseColorFactor[1], mat.baseColorFactor[2]);
                        worldSpaceSurfaceNormal = normalize(transformDirection(objectSpaceSurfaceNormal, objectToWorldSpaceTransform));
                    }

                } else if (usePerPrimitiveData) {
                    // Original Cornell box per-primitive path
                    Triangle triangle = *(const device Triangle*)intersection.primitive_data;
                    objectSpaceSurfaceNormal = interpolateVertexAttribute(triangle.normals, barycentric_coords);
                    surfaceColor = interpolateVertexAttribute(triangle.colors, barycentric_coords);
                } else
#endif
                {
                    // The ray hit a triangle. Look up the corresponding geometry's normal and UV buffers.
                    device TriangleResources & triangleResources = *(device TriangleResources *)((device char *)resources + resourcesStride * geometryIndex);

                    Triangle triangle;
                    triangle.normals[0] =  triangleResources.vertexNormals[triangleResources.indices[primitiveIndex * 3 + 0]];
                    triangle.normals[1] =  triangleResources.vertexNormals[triangleResources.indices[primitiveIndex * 3 + 1]];
                    triangle.normals[2] =  triangleResources.vertexNormals[triangleResources.indices[primitiveIndex * 3 + 2]];

                    triangle.colors[0] =  triangleResources.vertexColors[triangleResources.indices[primitiveIndex * 3 + 0]];
                    triangle.colors[1] =  triangleResources.vertexColors[triangleResources.indices[primitiveIndex * 3 + 1]];
                    triangle.colors[2] =  triangleResources.vertexColors[triangleResources.indices[primitiveIndex * 3 + 2]];

                    objectSpaceSurfaceNormal = interpolateVertexAttribute(triangle.normals, barycentric_coords);
                    surfaceColor = interpolateVertexAttribute(triangle.colors, barycentric_coords);
                }

                // Transform the normal from object to world space.
                worldSpaceSurfaceNormal = normalize(transformDirection(objectSpaceSurfaceNormal, objectToWorldSpaceTransform));
            }
            else if (mask & GEOMETRY_MASK_SPHERE) {
                Sphere sphere;
#if SUPPORTS_METAL_3
                if (usePerPrimitiveData) {
                    // Per-primitive data points to data from the specified buffer as was configured in the MTLAccelerationStructureBoundingBoxGeometryDescriptor.
                    sphere = *(const device Sphere*)intersection.primitive_data;
                } else
#endif
                {
                    // The ray hit a sphere. Look up the corresponding sphere buffer.
                    device SphereResources & sphereResources = *(device SphereResources *)((device char *)resources + resourcesStride * geometryIndex);
                    sphere = sphereResources.spheres[primitiveIndex];
                }

                // Transform the sphere's origin from object space to world space.
                float3 worldSpaceOrigin = transformPoint(sphere.origin, objectToWorldSpaceTransform);

                // Compute the surface normal directly in world space.
                worldSpaceSurfaceNormal = normalize(worldSpaceIntersectionPoint - worldSpaceOrigin);

                // The sphere is a uniform color, so you don't need to interpolate the color across the surface.
                surfaceColor = sphere.color;
            }

            // Capture debug data on first bounce
            if (bounce == 0 && bistroMode) {
                dbgHit = true;
                dbgSurfaceColor = surfaceColor;
                dbgWorldNormal = worldSpaceSurfaceNormal;
                dbgBarycentrics = float3(1.0f - barycentric_coords.x - barycentric_coords.y,
                                        barycentric_coords.x, barycentric_coords.y);
                dbgPrimitiveId = primitiveIndex;
                dbgInstanceId = instanceIndex;
                if (mask & GEOMETRY_MASK_TRIANGLE) {
                    const device GPUTriangleData &dbgTri = *(const device GPUTriangleData*)intersection.primitive_data;
                    dbgMaterialId = dbgTri.materialIndex;
                }
            }

            float3 worldSpaceLightDirection;
            float3 lightColor;
            float lightDistance;

            if (bistroMode) {
                // Sun direction from Euler(-63°, -23.4°, 0)
                worldSpaceLightDirection = normalize(float3(-0.1803f, 0.8910f, 0.4167f));
                lightDistance = INFINITY;

                // Sun: sRGB(1.0, 0.87, 0.78), full daylight intensity
                float3 sunRadiance = float3(1.0f, 0.87f, 0.78f) * 8.0f;
                // Sky ambient: cool blue fill
                float3 skyAmbient = float3(0.25f, 0.30f, 0.45f);

                if (uniforms.enablePBR) {
                    float3 V = -ray.direction;
                    lightColor = evaluatePBR(worldSpaceSurfaceNormal, V, worldSpaceLightDirection,
                                            surfaceColor, bistroMetallic, bistroRoughness, sunRadiance);
                    lightColor += surfaceColor * skyAmbient * (1.0f - bistroMetallic * 0.5f);
                } else {
                    float NdotL = saturate(dot(worldSpaceSurfaceNormal, worldSpaceLightDirection));
                    lightColor = float3(1.0f, 0.87f, 0.78f) * 2.5f * NdotL;
                    lightColor += skyAmbient;
                }
            } else {
                // Choose a random light source to sample.
                float lightSample = halton(offset + uniforms.frameIndex, 2 + bounce * 5 + 0);
                unsigned int lightIndex = min((unsigned int)(lightSample * uniforms.lightCount), uniforms.lightCount - 1);

                // Choose a random point to sample on the light source.
                float2 r = float2(halton(offset + uniforms.frameIndex, 2 + bounce * 5 + 1),
                                  halton(offset + uniforms.frameIndex, 2 + bounce * 5 + 2));

                // Sample the lighting between the intersection point and the point on the area light.
                sampleAreaLight(areaLights[lightIndex], r, worldSpaceIntersectionPoint, worldSpaceLightDirection,
                                lightColor, lightDistance);

                // Scale the light color by the cosine of the angle between the light direction and
                // surface normal.
                lightColor *= saturate(dot(worldSpaceSurfaceNormal, worldSpaceLightDirection));

                // Scale the light color by the number of lights to compensate for the fact that
                // the sample samples only one light source at random.
                lightColor *= uniforms.lightCount;
            }

            if (bistroMode) {
                // PBR path: cast shadow ray for sun visibility
                struct ray shadowRay;
                shadowRay.origin = worldSpaceIntersectionPoint + worldSpaceSurfaceNormal * 1e-3f;
                shadowRay.direction = worldSpaceLightDirection;
                shadowRay.max_distance = INFINITY;

                i.accept_any_intersection(true);
                intersection = i.intersect(shadowRay, accelerationStructure, RAY_MASK_SHADOW);

                float3 ambient = surfaceColor * float3(0.25f, 0.30f, 0.45f) * (1.0f - bistroMetallic * 0.5f);
                bool inShadow = (intersection.type != intersection_type::none);
                if (!inShadow)
                    accumulatedColor += lightColor * color;
                else
                    accumulatedColor += ambient * color; // shadow: ambient only

                if (bounce == 0) {
                    dbgShadow = inShadow ? 0.0f : 1.0f;
                    dbgNdotL = saturate(dot(worldSpaceSurfaceNormal, worldSpaceLightDirection));
                }

                // Attenuate for next bounce (diffuse-like)
                color *= surfaceColor;
            } else {
                // Original Cornell box Lambertian path
                color *= surfaceColor;

                struct ray shadowRay;
                shadowRay.origin = worldSpaceIntersectionPoint + worldSpaceSurfaceNormal * 1e-3f;
                shadowRay.direction = worldSpaceLightDirection;
                shadowRay.max_distance = lightDistance - 1e-3f;

                i.accept_any_intersection(true);

                if (useIntersectionFunctions)
                    intersection = i.intersect(shadowRay, accelerationStructure, RAY_MASK_SHADOW, intersectionFunctionTable);
                else
                    intersection = i.intersect(shadowRay, accelerationStructure, RAY_MASK_SHADOW);

                if (intersection.type == intersection_type::none)
                    accumulatedColor += lightColor * color;
            }

            // Choose a random direction to continue the path of the ray. This causes light to
            // bounce between surfaces. An app might evaluate a more complicated equation to
            // calculate the amount of light that reflects between intersection points.  However,
            // all the math in this kernel cancels out because this app assumes a simple diffuse
            // BRDF and samples the rays with a cosine distribution over the hemisphere (importance
            // sampling). This requires that the kernel only multiply the colors together. This
            // sampling strategy also reduces the amount of noise in the output image.
            r = float2(halton(offset + uniforms.frameIndex, 2 + bounce * 5 + 3),
                       halton(offset + uniforms.frameIndex, 2 + bounce * 5 + 4));

            float3 worldSpaceSampleDirection = sampleCosineWeightedHemisphere(r);
            worldSpaceSampleDirection = alignHemisphereWithNormal(worldSpaceSampleDirection, worldSpaceSurfaceNormal);

            ray.origin = worldSpaceIntersectionPoint + worldSpaceSurfaceNormal * 1e-3f;
            ray.direction = worldSpaceSampleDirection;
        }

        // Debug mode overrides
        if (bistroMode && uniforms.debugMode > 0 && dbgHit) {
            switch (uniforms.debugMode) {
                case 1: accumulatedColor = fract(float(dbgPrimitiveId) * float3(0.123f, 0.456f, 0.789f)); break; // Primitive ID
                case 2: accumulatedColor = fract(float(dbgMaterialId) * float3(0.31f, 0.57f, 0.91f)); break;     // Material ID
                case 3: accumulatedColor = dbgBarycentrics; break;                                                 // Barycentrics
                case 4: accumulatedColor = dbgSurfaceColor; break;                                                 // Base color (no lighting)
                case 5: accumulatedColor = dbgWorldNormal * 0.5f + 0.5f; break;                                    // World normal
                case 6: accumulatedColor = float3(dbgNdotL); break;                                                // NdotL (no shadow)
                case 7: accumulatedColor = float3(dbgShadow); break;                                              // Shadow visibility
                case 8: accumulatedColor = fract(float(dbgInstanceId) * float3(0.17f, 0.63f, 0.41f)); break;      // Instance ID
                case 9: { // Lambert (no tex): surfaceColor * NdotL
                    float3 L = normalize(float3(-0.1803f, 0.8910f, 0.4167f));
                    float ndl = saturate(dot(dbgWorldNormal, L));
                    accumulatedColor = dbgSurfaceColor * ndl + dbgSurfaceColor * 0.15f;
                    break;
                }
                case 10: accumulatedColor = float3(dbgUV, 0.0f); break;                                           // UV coordinates
                case 11: accumulatedColor = dbgBaseTexSample; break;                                               // Raw base color tex sample at actual UV
                case 12: accumulatedColor = float3(dbgAO); break;                                                  // AO value
                case 13: accumulatedColor = fract(float(dbgBaseTexIdx) * float3(0.17f, 0.53f, 0.91f)); break;      // Base tex index
                default: break;
            }
        }

        // Average this frame's sample with all of the previous frames.
        if (uniforms.frameIndex > 0) {
            float3 prevColor = prevTex.read(tid).xyz;
            prevColor *= uniforms.frameIndex;

            accumulatedColor += prevColor;
            accumulatedColor /= (uniforms.frameIndex + 1);
        }

        dstTex.write(float4(accumulatedColor, 1.0f), tid);
    }
}

// Screen filling quad in normalized device coordinates.
constant float2 quadVertices[] = {
    float2(-1, -1),
    float2(-1,  1),
    float2( 1,  1),
    float2(-1, -1),
    float2( 1,  1),
    float2( 1, -1)
};

struct CopyVertexOut {
    float4 position [[position]];
    float2 uv;
};

// Simple vertex shader that passes through NDC quad positions.
vertex CopyVertexOut copyVertex(unsigned short vid [[vertex_id]]) {
    float2 position = quadVertices[vid];

    CopyVertexOut out;

    out.position = float4(position, 0, 1);
    out.uv = position * 0.5f + 0.5f;

    return out;
}

// Simple fragment shader that copies a texture and applies a simple tonemapping function.
fragment float4 copyFragment(CopyVertexOut in [[stage_in]],
                             texture2d<float> tex)
{
    constexpr sampler sam(min_filter::nearest, mag_filter::nearest, mip_filter::none);

    float3 color = tex.sample(sam, in.uv).xyz;

    // Apply a simple tonemapping function to reduce the dynamic range of the
    // input image into a range which the screen can display.
    color = color / (1.0f + color);

    return float4(color, 1.0f);
}
