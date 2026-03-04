/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The implementation of the cross-platform app delegate.
*/
#import "AppDelegate.h"

#if TARGET_IOS

@interface AAPLWindowSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation AAPLWindowSceneDelegate

/// Configures the app's window property and attaches it to a scene.
///
/// - Parameters:
///   - scene: A scene that's connecting to the app.
///   - session: A session instance that has the configuration details for `scene`.
///   - options: Additional options for configuring the scene, such as when a person
///   selects a quick action.
///
/// This method is an opportunity for the app to configure the `window` property
/// and attach it to the `scene` argument.
/// If the app has a storyboard, UIKit automatically configures the
/// `window` property and attaches it to `scene` before calling this method.
///
/// > Note: The `scene` and `session` arguments might not be new instances
/// > (see `application:configurationForConnectingSceneSession`).
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {

    if (![scene isKindOfClass:[UIWindowScene class]]) {
        return;
    }
}

/// Notifies the app when UIKit disconnects a scene.
///
/// - Parameter scene: A scene that UIKit is disconnecting from the app.
///
/// This method is an opportunity for the app to release any resources that it
/// associates with `scene` that it can recreate if UIKit reconnects the scene.
///
/// > Note: UIKit can reconnect a scene unless it discards the scene's sessions
/// > (see `application:didDiscardSceneSessions`).
///
/// UIKit calls this method when it releases a scene shortly after it enters the
/// background or when it discards the scene's session.
- (void)sceneDidDisconnect:(UIScene *)scene {
    // Release resources for `scene` that the app can create again later.
}

@end

@implementation AAPLAppDelegate

/// Returns a configuration for UIKit when it creates a new scene.
///
/// - Parameters:
///   - application: The app's `UIApplication` singleton.
///   - connectingSceneSession: A session instance that contains configuration data
///   from the app's `Info.plist` file, if applicable.
///   - options: The system-specific options that configure the scene.
///
/// UIKit calls this method when it's creating a new session and applies the configuration
/// it returns.
- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options {

    UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:@"Default Configuration" sessionRole:connectingSceneSession.role];
    return configuration;
}

/// Notifies the app when UIKit discards scene sessions.
/// - Parameters:
///   - application: The app's `UIApplication` singleton.
///   - sceneSessions: A set of sessions that UIKit is discarding.
///
/// UIKit calls this method when a person discards a scene session,
/// or after launch if they discard the scene while the app isn't running.
- (void)application:(UIApplication *)application didDiscardSceneSessions:(NSSet<UISceneSession *> *)sceneSessions {
    // Release any resources specific to any scene in the `sceneSessions` set.
}

#elif TARGET_OS_OSX

@implementation AAPLAppDelegate

// Close app when window is closed
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app {
    return YES;
}
#endif

@end
