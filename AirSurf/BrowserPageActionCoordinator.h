#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class BrowserNavigationService;
@class BrowserVideoPlaybackCoordinator;
@class BrowserWebView;

NS_ASSUME_NONNULL_BEGIN

@protocol BrowserPageActionCoordinatorHost <NSObject>
- (void)browserPresentViewController:(UIViewController *)viewController;
- (BOOL)browserOpenRequestInNewTab:(NSURLRequest *)request;
- (void)browserLoadRequest:(NSURLRequest *)request;
- (void)browserShowStatus:(NSString *)message symbolName:(nullable NSString *)symbolName;
- (void)browserOpenMenu;
- (void)browserToggleFavoriteForCurrentPage;
- (BOOL)browserCurrentPageIsFavorite;
@end

/// What happens when the cursor hovers, clicks or is held on a point of the page.
@interface BrowserPageActionCoordinator : NSObject

- (instancetype)initWithHost:(id<BrowserPageActionCoordinatorHost>)host
           navigationService:(BrowserNavigationService *)navigationService
    videoPlaybackCoordinator:(BrowserVideoPlaybackCoordinator *)videoPlaybackCoordinator NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// `completion` reports whether the point is over something clickable. Calls are coalesced:
/// while one query is running only the most recent point is kept.
- (void)hoverAtPoint:(CGPoint)point webView:(BrowserWebView *)webView completion:(void (^)(BOOL interactive))completion;
- (void)clickAtPoint:(CGPoint)point webView:(BrowserWebView *)webView;
- (void)showActionsAtPoint:(CGPoint)point webView:(BrowserWebView *)webView;
- (void)scrollInnerContentAtPoint:(CGPoint)point delta:(CGPoint)delta webView:(BrowserWebView *)webView;

@end

NS_ASSUME_NONNULL_END
