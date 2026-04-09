#import "CameraController.h"
#import <Carbon/Carbon.h> // for kVK_ key codes

@implementation CameraController {
    bool _keys[256];
    BOOL _didMove;
}

- (instancetype)initWithPosition:(simd_float3)position
                          target:(simd_float3)target {
    self = [super init];
    if (self) {
        _position = position;
        _moveSpeed = 8.0f;
        _lookSensitivity = 0.003f;
        memset(_keys, 0, sizeof(_keys));

        // Derive yaw/pitch from initial direction
        simd_float3 dir = simd_normalize(target - position);
        _yaw = atan2f(dir.x, dir.z);
        _pitch = asinf(simd_clamp(dir.y, -0.999f, 0.999f));
        _didMove = NO;
    }
    return self;
}

- (simd_float3)forward {
    return simd_make_float3(
        sinf(_yaw) * cosf(_pitch),
        sinf(_pitch),
        cosf(_yaw) * cosf(_pitch)
    );
}

- (simd_float3)target {
    return _position + [self forward];
}

- (BOOL)didMove { return _didMove; }

- (BOOL)consumeDidMove {
    BOOL val = _didMove;
    _didMove = NO;
    return val;
}

- (void)updateWithDeltaTime:(float)dt {
    simd_float3 fwd = [self forward];
    simd_float3 right = simd_normalize(simd_cross(fwd, simd_make_float3(0, 1, 0)));
    simd_float3 up = simd_make_float3(0, 1, 0);

    float speed = _moveSpeed * dt;

    // Shift for faster movement
    if (_keys[kVK_Shift] || _keys[kVK_RightShift])
        speed *= 3.0f;

    simd_float3 move = {0, 0, 0};

    if (_keys[kVK_ANSI_W]) move += fwd * speed;
    if (_keys[kVK_ANSI_S]) move -= fwd * speed;
    if (_keys[kVK_ANSI_D]) move += right * speed;
    if (_keys[kVK_ANSI_A]) move -= right * speed;
    if (_keys[kVK_ANSI_E] || _keys[kVK_Space]) move += up * speed;
    if (_keys[kVK_ANSI_Q] || _keys[kVK_Control]) move -= up * speed;

    if (simd_length_squared(move) > 1e-8f) {
        _position += move;
        _didMove = YES;
    }
}

- (void)keyDown:(unsigned short)keyCode {
    if (keyCode < 256) _keys[keyCode] = true;
}

- (void)keyUp:(unsigned short)keyCode {
    if (keyCode < 256) _keys[keyCode] = false;
}

- (void)mouseMovedDeltaX:(float)dx deltaY:(float)dy {
    _yaw += dx * _lookSensitivity;
    _pitch -= dy * _lookSensitivity;

    // Clamp pitch to avoid gimbal lock
    float limit = 89.0f * (M_PI / 180.0f);
    _pitch = simd_clamp(_pitch, -limit, limit);

    _didMove = YES;
}

- (void)scrollWheelDeltaY:(float)dy {
    _moveSpeed = fmaxf(0.5f, _moveSpeed + dy * 0.5f);
}

@end
