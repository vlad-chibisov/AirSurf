#import "BrowserPreferencesStore.h"

// Defaults keys. They are stored on the device, so changing one resets that setting.
static NSString * const kMobileModeKey = @"MobileMode";
static NSString * const kToolbarAlwaysVisibleKey = @"ShowTopNavigationBar";
static NSString * const kPageZoomKey = @"PageZoomPercent";
static NSString * const kNativePlayerKey = @"NativeVideoPlayer";
static NSString * const kBlockPopupsKey = @"BlockPopups";
static NSString * const kUsageGuideSeenKey = @"HasSeenUsageGuide3";
static NSString * const kHomePageKey = @"homepage";
static NSString * const kSearchEngineKey = @"SearchEngine";
static NSString * const kCursorSpeedKey = @"CursorSpeed";

static NSUInteger BrowserClampedZoom(NSUInteger percent) {
    return MAX((NSUInteger)50, MIN((NSUInteger)200, percent));
}

@implementation BrowserPreferencesStore

+ (NSString *)nameForSearchEngine:(BrowserSearchEngine)searchEngine {
    switch (searchEngine) {
        case BrowserSearchEngineYandex: return @"Yandex";
        case BrowserSearchEngineDuckDuckGo: return @"DuckDuckGo";
        case BrowserSearchEngineBing: return @"Bing";
        default: return @"Google";
    }
}

+ (NSString *)nameForCursorSpeed:(BrowserCursorSpeed)cursorSpeed {
    switch (cursorSpeed) {
        case BrowserCursorSpeedSlow: return @"Slow";
        case BrowserCursorSpeedFast: return @"Fast";
        default: return @"Normal";
    }
}

#pragma mark - Defaults access

- (NSUserDefaults *)store {
    return NSUserDefaults.standardUserDefaults;
}

/// The stored number, or nil when the setting was never changed.
- (nullable NSNumber *)numberForKey:(NSString *)key {
    id value = [self.store objectForKey:key];
    return [value isKindOfClass:[NSNumber class]] ? value : nil;
}

- (BOOL)flagForKey:(NSString *)key fallback:(BOOL)fallback {
    NSNumber *value = [self numberForKey:key];
    return value != nil ? value.boolValue : fallback;
}

- (NSInteger)choiceForKey:(NSString *)key lowest:(NSInteger)lowest highest:(NSInteger)highest fallback:(NSInteger)fallback {
    NSNumber *value = [self numberForKey:key];
    if (value == nil || value.integerValue < lowest || value.integerValue > highest) {
        return fallback;
    }
    return value.integerValue;
}

#pragma mark - Settings

- (BOOL)mobileModeEnabled { return [self flagForKey:kMobileModeKey fallback:NO]; }
- (void)setMobileModeEnabled:(BOOL)enabled { [self.store setBool:enabled forKey:kMobileModeKey]; }

- (NSString *)userAgent {
    if (self.mobileModeEnabled) {
        return @"Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1";
    }
    return @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15";
}

- (BOOL)topNavigationBarVisible { return [self flagForKey:kToolbarAlwaysVisibleKey fallback:YES]; }
- (void)setTopNavigationBarVisible:(BOOL)visible { [self.store setBool:visible forKey:kToolbarAlwaysVisibleKey]; }

- (NSUInteger)pageZoomPercent {
    NSNumber *value = [self numberForKey:kPageZoomKey];
    // 125% makes most desktop layouts readable from the couch.
    return value != nil ? BrowserClampedZoom(value.unsignedIntegerValue) : 125;
}

- (void)setPageZoomPercent:(NSUInteger)percent {
    [self.store setInteger:(NSInteger)BrowserClampedZoom(percent) forKey:kPageZoomKey];
}

- (BOOL)nativeVideoPlayerEnabled { return [self flagForKey:kNativePlayerKey fallback:YES]; }
- (void)setNativeVideoPlayerEnabled:(BOOL)enabled { [self.store setBool:enabled forKey:kNativePlayerKey]; }

- (BOOL)blockPopups { return [self flagForKey:kBlockPopupsKey fallback:YES]; }
- (void)setBlockPopups:(BOOL)block { [self.store setBool:block forKey:kBlockPopupsKey]; }

- (BOOL)hasSeenUsageGuide { return [self flagForKey:kUsageGuideSeenKey fallback:NO]; }
- (void)setHasSeenUsageGuide:(BOOL)seen { [self.store setBool:seen forKey:kUsageGuideSeenKey]; }

- (NSString *)homePageURLString {
    id value = [self.store objectForKey:kHomePageKey];
    return [value isKindOfClass:[NSString class]] ? value : @"";
}

- (void)setHomePageURLString:(NSString *)URLString {
    [self.store setObject:URLString ?: @"" forKey:kHomePageKey];
}

- (BrowserSearchEngine)searchEngine {
    return (BrowserSearchEngine)[self choiceForKey:kSearchEngineKey lowest:BrowserSearchEngineGoogle highest:BrowserSearchEngineBing fallback:BrowserSearchEngineGoogle];
}

- (void)setSearchEngine:(BrowserSearchEngine)searchEngine {
    [self.store setInteger:searchEngine forKey:kSearchEngineKey];
}

- (BrowserCursorSpeed)cursorSpeed {
    return (BrowserCursorSpeed)[self choiceForKey:kCursorSpeedKey lowest:BrowserCursorSpeedSlow highest:BrowserCursorSpeedFast fallback:BrowserCursorSpeedNormal];
}

- (void)setCursorSpeed:(BrowserCursorSpeed)cursorSpeed {
    [self.store setInteger:cursorSpeed forKey:kCursorSpeedKey];
}

- (CGFloat)cursorSpeedMultiplier {
    switch (self.cursorSpeed) {
        case BrowserCursorSpeedSlow: return 0.65;
        case BrowserCursorSpeedFast: return 1.5;
        default: return 1.0;
    }
}

@end
