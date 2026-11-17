#import "AppDelegate.h"

#import "BrowserWebView.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary<UIApplicationLaunchOptionsKey, id> *)launchOptions {
    // Earlier builds stored the user agent string; it is now worked out from the mobile/desktop setting.
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"UserAgent"];
    // Cookies go back into WebKit before the first page loads.
    NSURL *caches = [[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
    NSData *cookieData = [NSData dataWithContentsOfURL:[caches URLByAppendingPathComponent:@"Cookies.data"]];
    if (cookieData.length == 0) {
        cookieData = [[NSUserDefaults standardUserDefaults] objectForKey:@"ApplicationCookie"];
    }
    if ([cookieData isKindOfClass:[NSData class]] && cookieData.length > 0) {
        [BrowserWebView restoreCookiesFromData:cookieData];
    }
    // Starts compiling the ad-blocking rules while the window comes up.
    [BrowserWebEnvironment sharedEnvironment];
    return YES;
}

- (UISceneConfiguration *)application:(UIApplication *)application
configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession
                              options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:@"Default" sessionRole:connectingSceneSession.role];
    configuration.delegateClass = NSClassFromString(@"SceneDelegate");
    return configuration;
}

@end
