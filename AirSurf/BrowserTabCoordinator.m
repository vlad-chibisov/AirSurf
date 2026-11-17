#import "BrowserTabCoordinator.h"

#import "BrowserLibraryStore.h"
#import "BrowserNavigationService.h"
#import "BrowserPreferencesStore.h"
#import "BrowserSessionStore.h"
#import "BrowserTabViewModel.h"
#import "BrowserViewModel.h"
#import "BrowserWebView.h"

@implementation BrowserTabCoordinator {
    __weak id<BrowserTabCoordinatorHost> _host;
    __weak UIView *_container;
    __weak id<BrowserWebViewDelegate> _webViewDelegate;
    BrowserViewModel *_tabs;
    BrowserPreferencesStore *_preferences;
    BrowserNavigationService *_navigation;
    BrowserSessionStore *_session;
    /// Keyed by tab identifier. Tabs that were never shown have no entry.
    NSMutableDictionary<NSString *, BrowserWebView *> *_liveWebViews;
}

- (instancetype)initWithHost:(id<BrowserTabCoordinatorHost>)host
                   viewModel:(BrowserViewModel *)viewModel
            preferencesStore:(BrowserPreferencesStore *)preferencesStore
           navigationService:(BrowserNavigationService *)navigationService
                sessionStore:(BrowserSessionStore *)sessionStore
               containerView:(UIView *)containerView
             webViewDelegate:(id<BrowserWebViewDelegate>)webViewDelegate {
    if ((self = [super init])) {
        _host = host;
        _tabs = viewModel;
        _preferences = preferencesStore;
        _navigation = navigationService;
        _session = sessionStore;
        _container = containerView;
        _webViewDelegate = webViewDelegate;
        _liveWebViews = [NSMutableDictionary new];
    }
    return self;
}

- (BrowserTabViewModel *)activeTab {
    return _tabs.activeTab;
}

- (NSUInteger)tabCount {
    return _tabs.tabs.count;
}

- (BOOL)isTabIndex:(NSInteger)index {
    return index >= 0 && index < (NSInteger)_tabs.tabs.count;
}

static void BrowserRunCompletion(void (^completion)(void)) {
    if (completion) {
        completion();
    }
}

#pragma mark - Web views

/// The tab's web view, created on first use at whatever the tab last showed.
- (BrowserWebView *)webViewForTab:(BrowserTabViewModel *)tab {
    BrowserWebView *existing = _liveWebViews[tab.identifier];
    if (existing) {
        return existing;
    }
    BrowserWebView *webView = [[BrowserWebView alloc] initWithUserAgent:_preferences.userAgent];
    webView.delegate = _webViewDelegate;
    webView.pageZoom = _preferences.pageZoomPercent / 100.0;
    webView.blocksPopups = _preferences.blockPopups;
    webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    webView.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    webView.scrollView.showsVerticalScrollIndicator = YES;
    _liveWebViews[tab.identifier] = webView;

    if (tab.interactionState.length > 0) {
        webView.interactionState = tab.interactionState;
    }
    // Restoring the back/forward state already loads the page; otherwise open the saved address.
    NSURLRequest *request = webView.request.URL == nil ? [_navigation requestForURLString:tab.URLString] : nil;
    if (request) {
        [webView loadRequest:request];
    }
    return webView;
}

/// Puts the front tab's web view in the container and takes every other one out.
- (void)showActiveWebView {
    BrowserTabViewModel *tab = self.activeTab;
    if (tab == nil) {
        return;
    }
    BrowserWebView *front = [self webViewForTab:tab];
    [_liveWebViews enumerateKeysAndObjectsUsingBlock:^(NSString *identifier, BrowserWebView *webView, BOOL *stop) {
        if (webView != front && webView.superview) {
            [webView pauseAllMediaPlayback];
            [webView removeFromSuperview];
        }
    }];
    UIView *container = _container;
    if (front.superview != container) {
        front.frame = container.bounds;
        [container addSubview:front];
    }
    _activeWebView = front;
    [_host tabCoordinatorDidChangeActiveTab];
}

- (void)discardWebViewForTab:(BrowserTabViewModel *)tab {
    BrowserWebView *webView = _liveWebViews[tab.identifier];
    [webView pauseAllMediaPlayback];
    [webView removeFromSuperview];
    [_liveWebViews removeObjectForKey:tab.identifier];
}

#pragma mark - Session

- (void)restoreSession {
    if ([_session restoreSessionIntoViewModel:_tabs]) {
        [self showActiveWebView];
        return;
    }
    BrowserTabViewModel *tab = [_tabs addTab];
    NSURLRequest *home = [_navigation homePageRequest];
    tab.showsStartPage = (home == nil);
    [self showActiveWebView];
    if (home) {
        [_activeWebView loadRequest:home];
    }
}

- (void)persistSession {
    for (BrowserTabViewModel *tab in _tabs.tabs) {
        BrowserWebView *webView = _liveWebViews[tab.identifier];
        NSData *history = webView.interactionState;
        if (history) {
            tab.interactionState = history;
        }
        NSString *address = webView.request.URL.absoluteString;
        if (address.length > 0) {
            tab.URLString = address;
        }
    }
    [_session saveSessionForViewModel:_tabs];
}

#pragma mark - Tabs

- (BOOL)openNewTabWithRequest:(NSURLRequest *)request {
    NSUInteger limit = [BrowserViewModel maximumTabCount];
    if (_tabs.tabs.count >= limit) {
        [_host tabCoordinatorShowStatus:[NSString stringWithFormat:@"Close a tab first: %lu is the limit", (unsigned long)limit]
                             symbolName:@"square.on.square"];
        return NO;
    }
    // Photograph the page being left while it is still on screen.
    [self captureSnapshotOfActiveTabWithCompletion:^{
        BrowserTabViewModel *tab = [self->_tabs addTab];
        if (tab == nil) {
            return;
        }
        tab.showsStartPage = (request == nil);
        [self showActiveWebView];
        if (request) {
            [self.activeWebView loadRequest:request];
        }
        [self persistSession];
    }];
    return YES;
}

- (void)switchToTabAtIndex:(NSInteger)tabIndex {
    if (![self isTabIndex:tabIndex]) {
        return;
    }
    void (^bringToFront)(void) = ^{
        [self->_tabs switchToTabAtIndex:tabIndex];
        [self showActiveWebView];
        [self persistSession];
    };
    if (tabIndex == _tabs.activeTabIndex) {
        bringToFront();
    } else {
        [self captureSnapshotOfActiveTabWithCompletion:bringToFront];
    }
}

- (void)closeTabAtIndex:(NSInteger)tabIndex {
    if (![self isTabIndex:tabIndex]) {
        return;
    }
    BrowserTabViewModel *tab = _tabs.tabs[(NSUInteger)tabIndex];
    [self discardWebViewForTab:tab];
    [tab removeStoredSnapshot];
    [_tabs removeTabAtIndex:tabIndex];
    // There is always at least one tab; closing the last one leaves a start page.
    if (_tabs.tabs.count == 0) {
        [_tabs addTab].showsStartPage = YES;
    }
    [self showActiveWebView];
    [self persistSession];
}

- (void)loadRequestInActiveTab:(NSURLRequest *)request {
    BrowserTabViewModel *tab = self.activeTab;
    if (tab == nil || request == nil) {
        return;
    }
    BOOL leavingStartPage = tab.showsStartPage;
    tab.showsStartPage = NO;
    [_activeWebView loadRequest:request];
    if (leavingStartPage) {
        [_host tabCoordinatorDidChangeActiveTab];
    }
}

- (void)showStartPageInActiveTab {
    BrowserTabViewModel *tab = self.activeTab;
    if (tab == nil || tab.showsStartPage) {
        return;
    }
    [self captureSnapshotOfActiveTabWithCompletion:nil];
    [_activeWebView pauseAllMediaPlayback];
    tab.showsStartPage = YES;
    [_host tabCoordinatorDidChangeActiveTab];
}

- (BOOL)hideStartPageInActiveTab {
    BrowserTabViewModel *tab = self.activeTab;
    BOOL hasPageBehind = _activeWebView.request.URL != nil;
    if (!tab.showsStartPage || !hasPageBehind) {
        return NO;
    }
    tab.showsStartPage = NO;
    [_host tabCoordinatorDidChangeActiveTab];
    return YES;
}

- (BrowserTabViewModel *)tabForWebView:(BrowserWebView *)webView {
    NSString *identifier = [_liveWebViews allKeysForObject:webView].firstObject;
    if (identifier == nil) {
        return nil;
    }
    NSUInteger index = [_tabs.tabs indexOfObjectPassingTest:^BOOL(BrowserTabViewModel *tab, NSUInteger idx, BOOL *stop) {
        return [tab.identifier isEqualToString:identifier];
    }];
    return index == NSNotFound ? nil : _tabs.tabs[index];
}

- (void)webViewDidFinishLoad:(BrowserWebView *)webView {
    BrowserTabViewModel *tab = [self tabForWebView:webView];
    if (tab == nil) {
        return;
    }
    NSURL *URL = webView.request.URL;
    NSString *pageTitle = webView.title ?: @"";
    tab.URLString = URL.absoluteString ?: @"";
    tab.title = pageTitle.length > 0 ? pageTitle : (URL.host ?: @"Untitled");
    [[BrowserLibraryStore sharedStore] recordVisitWithURLString:tab.URLString title:pageTitle];

    // Pages keep drawing for a moment after they report the load finished.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (tab == self.activeTab && webView == self.activeWebView && !tab.showsStartPage) {
            [self captureSnapshotOfActiveTabWithCompletion:nil];
        }
    });
    [self persistSession];
}

- (void)captureSnapshotOfActiveTabWithCompletion:(void (^)(void))completion {
    BrowserTabViewModel *tab = self.activeTab;
    BrowserWebView *webView = _activeWebView;
    BOOL pageOnScreen = tab != nil && !tab.showsStartPage && webView.superview != nil;
    if (!pageOnScreen) {
        BrowserRunCompletion(completion);
        return;
    }
    [webView takeSnapshotWithCompletion:^(UIImage *image) {
        if (image) {
            tab.snapshotImage = image;
        }
        BrowserRunCompletion(completion);
    }];
}

#pragma mark - Settings

- (void)applyPageZoom:(CGFloat)pageZoom {
    [_liveWebViews.allValues setValue:@(pageZoom) forKey:@"pageZoom"];
}

- (void)applyPopupBlocking:(BOOL)blocksPopups {
    [_liveWebViews.allValues setValue:@(blocksPopups) forKey:@"blocksPopups"];
}

- (void)recreateAllWebViews {
    [self persistSession];
    for (BrowserTabViewModel *tab in _tabs.tabs) {
        [self discardWebViewForTab:tab];
        // Load by address, so the first request already carries the new user agent.
        tab.interactionState = nil;
    }
    [self showActiveWebView];
}

@end
