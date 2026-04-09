#pragma once

#import <Foundation/Foundation.h>
#include <simd/simd.h>

/// FPS-style camera controller with WASD movement and mouse look.
/// Produces camera position/target per frame. Format-agnostic.
@interface CameraController : NSObject

@property (nonatomic) simd_float3 position;
@property (nonatomic) float yaw;    // radians, 0 = looking along +Z
@property (nonatomic) float pitch;  // radians, clamped to [-89, +89] degrees
@property (nonatomic) float moveSpeed;
@property (nonatomic) float lookSensitivity;

/// Whether the camera moved since last call to consumeDidMove.
@property (nonatomic, readonly) BOOL didMove;

- (instancetype)initWithPosition:(simd_float3)position
                          target:(simd_float3)target;

/// Compute forward direction from yaw/pitch.
- (simd_float3)forward;

/// Compute camera target from position + forward.
- (simd_float3)target;

/// Call once per frame with delta time to apply movement.
- (void)updateWithDeltaTime:(float)dt;

/// Reset didMove flag. Call after reading it.
- (BOOL)consumeDidMove;

// ---- Input events (macOS) ----
- (void)keyDown:(unsigned short)keyCode;
- (void)keyUp:(unsigned short)keyCode;
- (void)mouseMovedDeltaX:(float)dx deltaY:(float)dy;
- (void)scrollWheelDeltaY:(float)dy;

@end
