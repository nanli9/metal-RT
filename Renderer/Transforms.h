/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The header for simple matrix math functions.
*/

#ifndef Transforms_h
#define Transforms_h

#import <simd/simd.h>

matrix_float4x4 matrix4x4_translation(float tx, float ty, float tz);
matrix_float4x4 matrix4x4_rotation(float radians, vector_float3 axis);
matrix_float4x4 matrix4x4_scale(float sx, float sy, float sz);
matrix_float4x4 matrix4x4_perspective(float fovY, float aspect, float nearZ, float farZ);
matrix_float4x4 matrix4x4_look_at(vector_float3 eye, vector_float3 target, vector_float3 up);
matrix_float4x4 matrix4x4_inverse(matrix_float4x4 m);

#endif
