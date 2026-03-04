/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The header for the cross-platform app delegate.
*/

#if defined(TARGET_IOS)
@import UIKit;
#define PlatformAppDelegate UIResponder <UIApplicationDelegate>
#define PlatformWindow UIWindow
#else
@import AppKit;
#define PlatformAppDelegate NSObject <NSApplicationDelegate>
#define PlatformWindow NSWindow
#endif

@interface AAPLAppDelegate : PlatformAppDelegate

#if !TARGET_IOS
@property (strong, nonatomic) PlatformWindow *window;
#endif

@end
