/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The implementation of simple matrix math functions.
*/
#import "Transforms.h"

matrix_float4x4 matrix4x4_translation(float tx, float ty, float tz) {
    return (matrix_float4x4) {{
        { 1,   0,  0,  0 },
        { 0,   1,  0,  0 },
        { 0,   0,  1,  0 },
        { tx, ty, tz,  1 }
    }};
}

matrix_float4x4 matrix4x4_rotation(float radians, vector_float3 axis) {
    axis = vector_normalize(axis);
    float ct = cosf(radians);
    float st = sinf(radians);
    float ci = 1 - ct;
    float x = axis.x, y = axis.y, z = axis.z;

    return (matrix_float4x4) {{
        { ct + x * x * ci,     y * x * ci + z * st, z * x * ci - y * st, 0},
        { x * y * ci - z * st,     ct + y * y * ci, z * y * ci + x * st, 0},
        { x * z * ci + y * st, y * z * ci - x * st,     ct + z * z * ci, 0},
        {                   0,                   0,                   0, 1}
    }};
}

matrix_float4x4 matrix4x4_scale(float sx, float sy, float sz) {
    return (matrix_float4x4) {{
        { sx,  0,  0,  0 },
        { 0,  sy,  0,  0 },
        { 0,   0, sz,  0 },
        { 0,   0,  0,  1 }
    }};
}

matrix_float4x4 matrix4x4_perspective(float fovY, float aspect, float nearZ, float farZ) {
    float ys = 1.0f / tanf(fovY * 0.5f);
    float xs = ys / aspect;
    float zs = farZ / (nearZ - farZ);
    return (matrix_float4x4) {{
        { xs,  0,           0,  0 },
        {  0, ys,           0,  0 },
        {  0,  0,          zs, -1 },
        {  0,  0, nearZ * zs,  0 }
    }};
}

matrix_float4x4 matrix4x4_look_at(vector_float3 eye, vector_float3 target, vector_float3 up) {
    vector_float3 z = vector_normalize(eye - target); // forward points from target to eye (RH)
    vector_float3 x = vector_normalize(vector_cross(up, z));
    vector_float3 y = vector_cross(z, x);
    return (matrix_float4x4) {{
        { x.x, y.x, z.x, 0 },
        { x.y, y.y, z.y, 0 },
        { x.z, y.z, z.z, 0 },
        { -simd_dot(x, eye), -simd_dot(y, eye), -simd_dot(z, eye), 1 }
    }};
}

matrix_float4x4 matrix4x4_inverse(matrix_float4x4 m) {
    return simd_inverse(m);
}
