#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, BrowserSearchEngine) {
    BrowserSearchEngineGoogle = 0,
    BrowserSearchEngineYandex,
    BrowserSearchEngineDuckDuckGo,
    BrowserSearchEngineBing,
};

typedef NS_ENUM(NSInteger, BrowserCursorSpeed) {
    BrowserCursorSpeedSlow = 0,
    BrowserCursorSpeedNormal,
    BrowserCursorSpeedFast,
};

/// The user's settings, read from and written straight to user defaults.
@interface BrowserPreferencesStore : NSObject

+ (NSString *)nameForSearchEngine:(BrowserSearchEngine)searchEngine;
+ (NSString *)nameForCursorSpeed:(BrowserCursorSpeed)cursorSpeed;

/// Ask sites for their phone layout instead of the desktop one.
@property (nonatomic) BOOL mobileModeEnabled;
/// Safari's user agent for the layout chosen with mobileModeEnabled.
@property (nonatomic, readonly) NSString *userAgent;
/// NO: the toolbar stays hidden until the pointer is pushed against the top edge.
@property (nonatomic) BOOL topNavigationBarVisible;
/// Page zoom in percent, kept within 50...200.
@property (nonatomic) NSUInteger pageZoomPercent;
/// A page's full-screen button hands its video to the tvOS player.
@property (nonatomic) BOOL nativeVideoPlayerEnabled;
@property (nonatomic) BOOL blockPopups;
@property (nonatomic) BOOL hasSeenUsageGuide;
/// Empty means the built-in start page.
@property (nonatomic, copy) NSString *homePageURLString;
@property (nonatomic) BrowserSearchEngine searchEngine;
@property (nonatomic) BrowserCursorSpeed cursorSpeed;
@property (nonatomic, readonly) CGFloat cursorSpeedMultiplier;

@end

NS_ASSUME_NONNULL_END
