#import "SceneDelegate.h"

#import "BrowserWebView.h"
#import "ViewController.h"

static NSString * const kCookieDefaultsKey = @"ApplicationCookie";

@implementation SceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:[UIWindowScene class]]) {
        return;
    }
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.backgroundColor = UIColor.blackColor;
    self.window.rootViewController = [ViewController new];
    [self.window makeKeyAndVisible];
}

- (void)saveState {
    ViewController *viewController = (ViewController *)self.window.rootViewController;
    if ([viewController isKindOfClass:[ViewController class]]) {
        [viewController persistState];
    }
    // WebKit cannot keep its own website data on Apple TV hardware (Library is read-only for
    // apps), so cookies are saved here: in Caches, and in user defaults while they are small
    // enough not to eat into tvOS's ~500 KB defaults allowance.
    NSData *cookieData = [BrowserWebView cookieDataRepresentation];
    if (cookieData != nil) {
        NSURL *caches = [[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
        [cookieData writeToURL:[caches URLByAppendingPathComponent:@"Cookies.data"] atomically:YES];
        if (cookieData.length < 96 * 1024) {
            [[NSUserDefaults standardUserDefaults] setObject:cookieData forKey:kCookieDefaultsKey];
        } else {
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:kCookieDefaultsKey];
        }
    }
}

- (void)sceneWillResignActive:(UIScene *)scene {
    [self saveState];
}

- (void)sceneDidEnterBackground:(UIScene *)scene {
    [self saveState];
}

@end
