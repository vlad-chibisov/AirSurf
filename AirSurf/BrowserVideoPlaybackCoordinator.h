#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class BrowserMediaCandidate;
@class BrowserWebView;

NS_ASSUME_NONNULL_BEGIN

@protocol BrowserVideoPlaybackCoordinatorHost <NSObject>
@property (nonatomic, readonly, nullable) BrowserWebView *browserWebView;
@property (nonatomic, readonly) BOOL browserNativeVideoPlayerEnabled;
@property (nonatomic, readonly) NSString *browserUserAgent;
- (void)browserPresentViewController:(UIViewController *)viewController;
- (void)browserShowStatus:(NSString *)message symbolName:(nullable NSString *)symbolName;
@end

/// Decides when a video on a page is handed to the native player, and with which stream.
///
/// Nothing is handed over on its own. Clicking a video plays it in the page, so the site's
/// own player can be used to pick the voice-over, episode or quality. The page's fullscreen
/// button (or Hold Click › Play Video Full Screen) then hands the stream the page is playing,
/// at its current position, to the Apple TV player.
@interface BrowserVideoPlaybackCoordinator : NSObject

- (instancetype)initWithHost:(id<BrowserVideoPlaybackCoordinatorHost>)host NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Feed in the page agent's answer to a click.
- (void)noteClickResult:(NSDictionary *)result inWebView:(BrowserWebView *)webView;
- (void)webView:(BrowserWebView *)webView didRequestFullscreenVideo:(NSDictionary *)info;
- (void)webViewDidNavigate:(BrowserWebView *)webView;

/// Streams the player can open, best first.
- (NSArray<BrowserMediaCandidate *> *)playableCandidatesInWebView:(nullable BrowserWebView *)webView;
- (void)playCandidate:(BrowserMediaCandidate *)candidate fromWebView:(BrowserWebView *)webView;
/// A link straight to a video file or playlist. Returns YES if the player took it.
- (BOOL)playMediaURLIfPossible:(NSURL *)URL referrer:(nullable NSString *)referrer title:(nullable NSString *)title;
+ (BOOL)URLLooksLikeMedia:(NSURL *)URL;

@end

NS_ASSUME_NONNULL_END
