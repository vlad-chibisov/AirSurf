#import <UIKit/UIKit.h>

@class BrowserNavigationService, BrowserPreferencesStore, BrowserSessionStore;
@class BrowserTabViewModel, BrowserViewModel, BrowserWebView;
@protocol BrowserWebViewDelegate;

NS_ASSUME_NONNULL_BEGIN

@protocol BrowserTabCoordinatorHost <NSObject>
- (void)tabCoordinatorDidChangeActiveTab;
- (void)tabCoordinatorShowStatus:(NSString *)message symbolName:(nullable NSString *)symbolName;
@end

/// Gives every tab its own web view, created the first time the tab is shown, and keeps the
/// tab list, the saved session and the web view on screen in step.
@interface BrowserTabCoordinator : NSObject

@property (nonatomic, readonly, nullable) BrowserWebView *activeWebView;
@property (nonatomic, readonly, nullable) BrowserTabViewModel *activeTab;
@property (nonatomic, readonly) NSUInteger tabCount;

- (instancetype)initWithHost:(id<BrowserTabCoordinatorHost>)host
                   viewModel:(BrowserViewModel *)viewModel
            preferencesStore:(BrowserPreferencesStore *)preferencesStore
           navigationService:(BrowserNavigationService *)navigationService
                sessionStore:(BrowserSessionStore *)sessionStore
               containerView:(UIView *)containerView
             webViewDelegate:(id<BrowserWebViewDelegate>)webViewDelegate NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Brings back the saved tabs, or opens a single tab at the home page.
- (void)restoreSession;
- (void)persistSession;

/// A nil request opens the start page. NO when the tab limit is reached.
- (BOOL)openNewTabWithRequest:(nullable NSURLRequest *)request;
- (void)switchToTabAtIndex:(NSInteger)tabIndex;
- (void)closeTabAtIndex:(NSInteger)tabIndex;

- (void)loadRequestInActiveTab:(NSURLRequest *)request;
- (void)showStartPageInActiveTab;
/// Returns to the page the start page was covering; NO when the tab has no page yet.
- (BOOL)hideStartPageInActiveTab;

- (nullable BrowserTabViewModel *)tabForWebView:(BrowserWebView *)webView;
- (void)webViewDidFinishLoad:(BrowserWebView *)webView;
- (void)captureSnapshotOfActiveTabWithCompletion:(void (^ _Nullable)(void))completion;

- (void)applyPageZoom:(CGFloat)pageZoom;
- (void)applyPopupBlocking:(BOOL)blocksPopups;
/// After the user agent changes: every tab gets a new web view that reloads its address.
- (void)recreateAllWebViews;

@end

NS_ASSUME_NONNULL_END
