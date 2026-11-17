#import <UIKit/UIKit.h>

@class BrowserMediaCandidate;
@class BrowserPreferencesStore;
@class BrowserWebView;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, BrowserPreferenceChange) {
    BrowserPreferenceChangePageZoom = 0,
    BrowserPreferenceChangeToolbar,
    BrowserPreferenceChangeUserAgent,
    BrowserPreferenceChangePopups,
    BrowserPreferenceChangeCursorSpeed,
    BrowserPreferenceChangeContentBlocking,
};

@protocol BrowserMenuCoordinatorHost <NSObject>
@property (nonatomic, readonly, nullable) BrowserWebView *browserWebView;
@property (nonatomic, readonly) BOOL browserShowingStartPage;
- (void)browserPresentViewController:(UIViewController *)viewController;
- (void)browserShowStatus:(NSString *)message symbolName:(nullable NSString *)symbolName;
- (void)browserLoadURLString:(NSString *)URLString;
- (void)browserOpenURLStringInNewTab:(NSString *)URLString;
- (void)browserShowStartPage;
- (void)browserShowTabOverview;
- (void)browserOpenNewTab;
- (void)browserShowAddressEntry;
- (void)browserToggleFavoriteForCurrentPage;
- (BOOL)browserCurrentPageIsFavorite;
- (NSArray<BrowserMediaCandidate *> *)browserPlayableVideos;
- (void)browserPlayVideo:(BrowserMediaCandidate *)candidate;
- (void)browserPreferencesDidChange:(BrowserPreferenceChange)change;
@end

/// The side-panel menu and the screens reached from it.
@interface BrowserMenuCoordinator : NSObject

- (instancetype)initWithHost:(id<BrowserMenuCoordinatorHost>)host
            preferencesStore:(BrowserPreferencesStore *)preferencesStore NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)showMenu;
- (void)showFavorites;
- (void)showHistory;
- (void)showUsageGuide;
- (void)showSettings;
/// The menu with Settings already opened inside it (the usual path, used for testing).
- (void)showMenuThenSettings;
/// Actions for a favourite or recent site (rename, remove, open in new tab).
- (void)showActionsForURLString:(NSString *)URLString title:(NSString *)title isFavorite:(BOOL)isFavorite;

@end

NS_ASSUME_NONNULL_END
