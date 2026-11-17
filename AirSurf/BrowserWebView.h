#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class BrowserWebView;

typedef NS_ENUM(NSInteger, BrowserMediaKind) {
    BrowserMediaKindHLS = 0,
    BrowserMediaKindFile,
    BrowserMediaKindUnsupported,
};

/// A video stream the page agent noticed in some frame of a page.
@interface BrowserMediaCandidate : NSObject

@property (nonatomic, strong, readonly) NSURL *URL;
@property (nonatomic, readonly) BrowserMediaKind kind;
/// URL of the frame that loaded the stream. Used as Referer / Origin for playback.
@property (nonatomic, copy, readonly) NSString *frameURLString;
@property (nonatomic, readonly) BOOL fromMainFrame;
/// The stream is (or was) attached to a <video> element, not just fetched by script.
@property (nonatomic, readonly) BOOL fromElement;
@property (nonatomic, readonly) BOOL isMasterPlaylist;
@property (nonatomic, readonly) BOOL isMediaPlaylist;
@property (nonatomic, readonly) BOOL muted;
@property (nonatomic, readonly) BOOL loops;
@property (nonatomic, readonly) BOOL started;
@property (nonatomic, readonly) CGSize elementSize;
@property (nonatomic, readonly) NSTimeInterval duration;
@property (nonatomic, strong, readonly) NSDate *firstSeen;
@property (nonatomic, copy, readonly) NSString *pageTitle;

@property (nonatomic, readonly) BOOL isPlayableNatively;
/// Short human readable label, e.g. "HLS stream - cdn.example.com".
@property (nonatomic, readonly) NSString *displayName;

@end

@protocol BrowserWebViewDelegate <NSObject>
@optional
- (BOOL)webView:(BrowserWebView *)webView shouldStartLoadWithRequest:(nullable NSURLRequest *)request navigationType:(NSInteger)navigationType;
- (BOOL)webView:(BrowserWebView *)webView shouldCreateNewTabWithRequest:(nullable NSURLRequest *)request navigationType:(NSInteger)navigationType;
- (void)webViewDidStartLoad:(BrowserWebView *)webView;
- (void)webViewDidFinishLoad:(BrowserWebView *)webView;
- (void)webView:(BrowserWebView *)webView didFailLoadWithError:(NSError *)error;
/// Title, URL, loading progress or back/forward availability changed.
- (void)webViewDidUpdateState:(BrowserWebView *)webView;
- (void)webView:(BrowserWebView *)webView didDetectMedia:(BrowserMediaCandidate *)candidate;
/// A <video> element started playing. `info` has width/height/muted/duration/src/blob and frameURL.
- (void)webView:(BrowserWebView *)webView videoDidStartPlaying:(NSDictionary *)info;
- (void)webView:(BrowserWebView *)webView didBlockPopupWithRequest:(nullable NSURLRequest *)request;
/// The page asked to show a video full screen (its own fullscreen button). `info` has
/// src (http only), blob, video (width/height/position/...), frameURL and mainFrame.
- (void)webView:(BrowserWebView *)webView didRequestFullscreenVideo:(NSDictionary *)info;
@end

/// One tab's page: a WKWebView (created at runtime, since WebKit isn't public on tvOS) plus the
/// page agent that reports videos and carries out the pointer's clicks and scrolls.
@interface BrowserWebView : UIView

- (instancetype)initWithUserAgent:(nullable NSString *)userAgent NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithFrame:(CGRect)frame NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

/// NO when WebKit could not be loaded; a web view is then an empty black view.
+ (BOOL)isWebKitAvailable;

@property (nonatomic, weak, nullable) id<BrowserWebViewDelegate> delegate;

#pragma mark Page state

/// The page's address, or the last requested one while nothing is loaded.
@property (nonatomic, readonly, nullable) NSURLRequest *request;
@property (nonatomic, readonly, nullable, copy) NSString *title;
@property (nonatomic, readonly, nullable) UIScrollView *scrollView;
@property (nonatomic, readonly, getter=isLoading) BOOL loading;
@property (nonatomic, readonly) double estimatedProgress;
@property (nonatomic, readonly) BOOL canGoBack;
@property (nonatomic, readonly) BOOL canGoForward;
/// Back/forward list and scroll position, to bring a tab back after a relaunch.
@property (nonatomic, nullable) NSData *interactionState;
/// Requests the content blocker stopped since the last top-level navigation.
@property (nonatomic, readonly) NSUInteger blockedRequestCount;
/// Streams seen since the last top-level navigation, oldest first.
@property (nonatomic, readonly) NSArray<BrowserMediaCandidate *> *mediaCandidates;

#pragma mark Behaviour

/// 1.0 is 100%.
@property (nonatomic) CGFloat pageZoom;
@property (nonatomic) BOOL blocksPopups;
- (void)setUserAgent:(nullable NSString *)userAgent;

#pragma mark Actions

- (void)loadRequest:(nullable NSURLRequest *)request;
- (void)reload;
- (void)stopLoading;
- (void)goBack;
- (void)goForward;
- (void)pauseAllMediaPlayback;
- (void)evaluateJavaScript:(NSString *)script completion:(void (^ _Nullable)(id _Nullable result))completion;

/// Runs a page agent command ("hover", "click", "context", "setText", "setSelect", "scroll")
/// at a point given in this view's coordinates. The command is routed into whichever frame
/// is under the point. `completion` is always called, with nil on timeout.
- (void)performPointCommand:(NSString *)command
                    atPoint:(CGPoint)point
                       data:(nullable NSDictionary *)data
                 completion:(void (^ _Nullable)(NSDictionary * _Nullable result))completion;

/// Small image of the visible page for the tab overview.
- (void)takeSnapshotWithCompletion:(void (^)(UIImage * _Nullable image))completion;
/// Page background or theme colour, for tinting the chrome behind the toolbar.
- (void)fetchPageColorWithCompletion:(void (^)(UIColor * _Nullable color))completion;

#pragma mark Website data (shared by all tabs)

+ (NSArray<NSHTTPCookie *> *)allCookies;
/// An archive of every cookie, written out when the app goes to the background.
+ (nullable NSData *)cookieDataRepresentation;
/// Puts archived cookies back; returns once WebKit has them (or after a few seconds).
+ (void)restoreCookiesFromData:(nullable NSData *)cookieData;
/// Everything but cookies.
+ (void)clearCachedDataWithCompletion:(void (^ _Nullable)(void))completion;
+ (void)clearCookiesWithCompletion:(void (^ _Nullable)(void))completion;
+ (void)resetWebsiteDataWithCompletion:(void (^ _Nullable)(void))completion;

@end

/// Process-wide WebKit state shared by every tab: the page agent script, the script
/// message channel and the content blocker.
@interface BrowserWebEnvironment : NSObject

+ (instancetype)sharedEnvironment;

/// nil when WebKit could not be loaded.
@property (nonatomic, readonly, nullable) id userContentController;
@property (nonatomic, readonly) NSString *agentToken;

/// Content blocking. Changing this takes effect for subsequent page loads.
@property (nonatomic) BOOL contentBlockingEnabled;
@property (nonatomic, readonly) BOOL contentBlockingAvailable;
@property (nonatomic, readonly) NSUInteger contentRuleCount;
/// Human readable state: "Ready", "Preparing", "Unavailable".
@property (nonatomic, readonly) NSString *contentBlockingStatus;
/// Runs `block` once the ad-blocking rules are attached (or failed), or after `timeout`.
/// Pages loaded before that point would be loaded without blocking.
- (void)performWhenContentBlockingReady:(void (^)(void))block timeout:(NSTimeInterval)timeout;
/// Why blocking is unavailable, for the Settings footer.
@property (nonatomic, readonly, nullable) NSString *contentBlockingFailureReason;

@end

NS_ASSUME_NONNULL_END
