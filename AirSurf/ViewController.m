#import "ViewController.h"

#import "BrowserCursorView.h"
#import "BrowserHUDView.h"
#import "BrowserLibraryStore.h"
#import "BrowserMenuCoordinator.h"
#import "BrowserNavigationService.h"
#import "BrowserPageActionCoordinator.h"
#import "BrowserPreferencesStore.h"
#import "BrowserRemoteInputController.h"
#import "BrowserSessionStore.h"
#import "BrowserStartPageView.h"
#import "BrowserTabCoordinator.h"
#import "BrowserTabOverviewController.h"
#import "BrowserTabViewModel.h"
#import "BrowserTheme.h"
#import "BrowserTopBarView.h"
#import "BrowserVideoPlaybackCoordinator.h"
#import "BrowserViewModel.h"
#import "BrowserWebView.h"

extern NSString * const BrowserGlobalSelectPressEndedNotification;

/// Pointer this close to the top edge reveals a hidden toolbar.
static CGFloat const kToolbarRevealEdge = 28.0;

@interface ViewController () <BrowserWebViewDelegate,
                              BrowserTabCoordinatorHost,
                              BrowserRemoteInputControllerHost,
                              BrowserTopBarViewDelegate,
                              BrowserStartPageViewDelegate,
                              BrowserTabOverviewControllerDelegate,
                              BrowserMenuCoordinatorHost,
                              BrowserPageActionCoordinatorHost,
                              BrowserVideoPlaybackCoordinatorHost>

@property (nonatomic) BrowserPreferencesStore *preferencesStore;
@property (nonatomic) BrowserNavigationService *navigationService;
@property (nonatomic) BrowserViewModel *viewModel;
@property (nonatomic) BrowserTabCoordinator *tabCoordinator;
@property (nonatomic) BrowserRemoteInputController *inputController;
@property (nonatomic) BrowserVideoPlaybackCoordinator *videoCoordinator;
@property (nonatomic) BrowserPageActionCoordinator *pageActionCoordinator;
@property (nonatomic) BrowserMenuCoordinator *menuCoordinator;

@property (nonatomic) UIView *webContainerView;
@property (nonatomic) BrowserStartPageView *startPageView;
@property (nonatomic) BrowserTopBarView *topBar;
@property (nonatomic) BrowserHUDView *hudView;
@property (nonatomic) UILabel *unavailableLabel;

@property (nonatomic) BOOL toolbarRevealed;
@property (nonatomic) BOOL lastPointerActive;
@property (nonatomic) NSTimer *stateTimer;
@property (nonatomic, weak) BrowserTabOverviewController *tabOverview;
@property (nonatomic) BOOL didShowFirstLaunchGuide;
@property (nonatomic) BOOL pointerStateInitialized;

@end

@implementation ViewController

#pragma mark Lifecycle

- (void)loadView {
    UIView *view = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 1920.0, 1080.0)];
    view.backgroundColor = UIColor.blackColor;
    self.view = view;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.preferencesStore = [BrowserPreferencesStore new];
    self.navigationService = [[BrowserNavigationService alloc] initWithPreferencesStore:self.preferencesStore];
    self.viewModel = [BrowserViewModel new];

    self.webContainerView = [[UIView alloc] initWithFrame:self.view.bounds];
    self.webContainerView.backgroundColor = UIColor.blackColor;
    self.webContainerView.clipsToBounds = YES;
    [self.view addSubview:self.webContainerView];

    self.startPageView = [[BrowserStartPageView alloc] initWithFrame:self.view.bounds];
    self.startPageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.startPageView.delegate = self;
    self.startPageView.topInset = [BrowserTopBarView preferredHeight];
    self.startPageView.hidden = YES;
    [self.view addSubview:self.startPageView];

    self.topBar = [[BrowserTopBarView alloc] initWithFrame:CGRectMake(0.0, 0.0, CGRectGetWidth(self.view.bounds), [BrowserTopBarView preferredHeight])];
    self.topBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.topBar.delegate = self;
    [self.view addSubview:self.topBar];

    self.hudView = [[BrowserHUDView alloc] initWithFrame:self.view.bounds];
    self.hudView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.hudView];

    self.inputController = [[BrowserRemoteInputController alloc] initWithHost:self rootView:self.view];
    self.inputController.speedMultiplier = self.preferencesStore.cursorSpeedMultiplier;
    [self.view addSubview:self.inputController.cursorView];

    self.videoCoordinator = [[BrowserVideoPlaybackCoordinator alloc] initWithHost:self];
    self.pageActionCoordinator = [[BrowserPageActionCoordinator alloc] initWithHost:self
                                                                  navigationService:self.navigationService
                                                           videoPlaybackCoordinator:self.videoCoordinator];
    self.menuCoordinator = [[BrowserMenuCoordinator alloc] initWithHost:self preferencesStore:self.preferencesStore];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleGlobalSelectPressEnded:)
                                                 name:BrowserGlobalSelectPressEndedNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleLibraryChange:)
                                                 name:BrowserLibraryDidChangeNotification
                                               object:nil];

    if (![BrowserWebView isWebKitAvailable]) {
        [self showWebKitUnavailableMessage];
        return;
    }

    self.tabCoordinator = [[BrowserTabCoordinator alloc] initWithHost:self
                                                            viewModel:self.viewModel
                                                     preferencesStore:self.preferencesStore
                                                    navigationService:self.navigationService
                                                         sessionStore:[BrowserSessionStore new]
                                                        containerView:self.webContainerView
                                                      webViewDelegate:self];
    __weak typeof(self) weakSelf = self;
    [[BrowserWebEnvironment sharedEnvironment] performWhenContentBlockingReady:^{
        [weakSelf.tabCoordinator restoreSession];
        [weakSelf refreshToolbar];
    } timeout:2.0];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.stateTimer == nil) {
        // Presented alerts and panels go away without telling us; this keeps the pointer in step.
        self.stateTimer = [NSTimer scheduledTimerWithTimeInterval:0.25 target:self selector:@selector(refreshPointerState) userInfo:nil repeats:YES];
        self.stateTimer.tolerance = 0.1;
    }
    [self refreshPointerState];
#if DEBUG
    if ([self runDebugAutomationIfRequested]) {
        return;
    }
#endif
    if (!self.preferencesStore.hasSeenUsageGuide && !self.didShowFirstLaunchGuide && self.tabCoordinator != nil) {
        self.didShowFirstLaunchGuide = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            self.preferencesStore.hasSeenUsageGuide = YES;
            [self.menuCoordinator showUsageGuide];
        });
    }
}

#if DEBUG
/// Test hook for the simulator, where there is no way to script the Siri Remote:
///   -DebugURL <url>           open a page at launch
///   -DebugClicks "x,y@s;..."  click screen point (x,y) s seconds after launch
///   -DebugMenu <s>            open the menu after s seconds
- (BOOL)runDebugAutomationIfRequested {
    static BOOL ran = NO;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *URLString = [defaults stringForKey:@"DebugURL"];
    NSString *clicks = [defaults stringForKey:@"DebugClicks"];
    double menuDelay = [defaults doubleForKey:@"DebugMenu"];
    NSString *scroll = [defaults stringForKey:@"DebugScroll"];
    NSString *evaluation = [defaults stringForKey:@"DebugEval"];
    NSString *actions = [defaults stringForKey:@"DebugActions"];
    if (ran || (URLString.length == 0 && clicks.length == 0 && menuDelay <= 0.0 && actions.length == 0)) {
        return NO;
    }
    ran = YES;
    self.preferencesStore.hasSeenUsageGuide = YES;
    if (URLString.length > 0) {
        // After the saved tabs are restored, which itself waits for the ad-blocking rules.
        [[BrowserWebEnvironment sharedEnvironment] performWhenContentBlockingReady:^{
            [self browserLoadURLString:URLString];
        } timeout:2.0];
    }
    for (NSString *step in [clicks componentsSeparatedByString:@";"]) {
        NSArray<NSString *> *parts = [step componentsSeparatedByString:@"@"];
        NSArray<NSString *> *coordinates = [parts.firstObject componentsSeparatedByString:@","];
        if (parts.count != 2 || coordinates.count != 2) {
            continue;
        }
        CGPoint point = CGPointMake(coordinates[0].doubleValue, coordinates[1].doubleValue);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(parts[1].doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSLog(@"[Debug] click at %@", NSStringFromCGPoint(point));
            [self.inputController moveCursorToPoint:point];
            [self inputControllerDidClickAtPoint:point];
        });
    }
    NSArray<NSString *> *scrollParts = [scroll componentsSeparatedByString:@"@"];
    if (scrollParts.count == 2) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(scrollParts[1].doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.tabCoordinator.activeWebView.scrollView setContentOffset:CGPointMake(0.0, scrollParts[0].doubleValue) animated:NO];
            NSLog(@"[Debug] scrolled to %@", scrollParts[0]);
        });
    }
    NSRange separator = [evaluation rangeOfString:@"@" options:NSBackwardsSearch];
    if (separator.location != NSNotFound) {
        NSString *script = [evaluation substringToIndex:separator.location];
        double delay = [evaluation substringFromIndex:separator.location + 1].doubleValue;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.tabCoordinator.activeWebView evaluateJavaScript:script completion:^(id result) {
                NSLog(@"[Debug] eval: %@", result);
                NSURL *caches = [[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
                [(result != nil ? [result description] : @"<nil: script threw or returned undefined>") writeToURL:[caches URLByAppendingPathComponent:@"debug-eval.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
            }];
        });
    }
    // -DebugActions "startpage@2;tabs@5;newtab@1;dismiss@7"
    for (NSString *step in [actions componentsSeparatedByString:@";"]) {
        NSArray<NSString *> *parts = [step componentsSeparatedByString:@"@"];
        if (parts.count != 2) {
            continue;
        }
        NSString *name = parts[0];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(parts[1].doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSLog(@"[Debug] action %@", name);
            if ([name isEqualToString:@"startpage"]) {
                [self browserShowStartPage];
            } else if ([name isEqualToString:@"tabs"]) {
                [self browserShowTabOverview];
            } else if ([name isEqualToString:@"newtab"]) {
                [self.tabCoordinator openNewTabWithRequest:nil];
            } else if ([name isEqualToString:@"dismiss"]) {
                [self dismissViewControllerAnimated:YES completion:nil];
            } else if ([name isEqualToString:@"scrollmode"]) {
                self.inputController.scrollModeEnabled = YES;
            } else if ([name isEqualToString:@"hold"]) {
                [self inputControllerDidHoldAtPoint:self.inputController.cursorPoint];
            } else if ([name isEqualToString:@"settings"]) {
                [self.menuCoordinator showMenuThenSettings];
            } else if ([name isEqualToString:@"address"]) {
                [self browserShowAddressEntry];
            }
        });
    }
    if (menuDelay > 0.0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(menuDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.menuCoordinator showMenu];
        });
    }
    return YES;
}
#endif

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutChrome];
}

- (void)dealloc {
    [self.stateTimer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)persistState {
    [self.tabCoordinator persistSession];
}

- (void)showWebKitUnavailableMessage {
    self.topBar.hidden = YES;
    self.unavailableLabel = [[UILabel alloc] initWithFrame:CGRectInset(self.view.bounds, 200.0, 200.0)];
    self.unavailableLabel.numberOfLines = 0;
    self.unavailableLabel.textAlignment = NSTextAlignmentCenter;
    self.unavailableLabel.textColor = [BrowserTheme primaryTextColor];
    self.unavailableLabel.font = [UIFont systemFontOfSize:36.0 weight:UIFontWeightMedium];
    self.unavailableLabel.text = @"This version of tvOS does not include the web engine this app needs.";
    [self.view addSubview:self.unavailableLabel];
}

#pragma mark State

- (BOOL)showingStartPage {
    return self.tabCoordinator.activeTab.showsStartPage;
}

- (BOOL)toolbarPinned {
    return self.preferencesStore.topNavigationBarVisible || [self showingStartPage];
}

- (BOOL)toolbarVisible {
    return [self toolbarPinned] || self.toolbarRevealed;
}

- (void)layoutChrome {
    CGRect bounds = self.view.bounds;
    CGFloat barHeight = [BrowserTopBarView preferredHeight];
    BOOL pinned = [self toolbarPinned];
    self.webContainerView.frame = pinned ? CGRectMake(0.0, barHeight, CGRectGetWidth(bounds), CGRectGetHeight(bounds) - barHeight) : bounds;
    BOOL visible = [self toolbarVisible];
    self.topBar.alpha = visible ? 1.0 : 0.0;
    self.topBar.transform = visible ? CGAffineTransformIdentity : CGAffineTransformMakeTranslation(0.0, -barHeight);
}

- (void)setToolbarRevealed:(BOOL)toolbarRevealed {
    if (_toolbarRevealed == toolbarRevealed) {
        return;
    }
    _toolbarRevealed = toolbarRevealed;
    if (!toolbarRevealed) {
        [self.topBar clearHover];
    }
    [BrowserTheme animate:^{
        [self layoutChrome];
    }];
}

- (BOOL)pointerActive {
    return self.tabCoordinator != nil &&
        self.presentedViewController == nil &&
        ![self showingStartPage] &&
        self.view.window != nil;
}

- (void)refreshPointerState {
    BOOL active = [self pointerActive];
    if (active == self.lastPointerActive && self.pointerStateInitialized) {
        return;
    }
    self.pointerStateInitialized = YES;
    self.lastPointerActive = active;
    [self.inputController refreshPointerState];
    if (!active) {
        self.inputController.scrollModeEnabled = NO;
        self.toolbarRevealed = NO;
        [self.topBar clearHover];
    } else {
        [self inputControllerCursorDidMoveToPoint:self.inputController.cursorPoint];
    }
    self.topBar.focusEnabled = !active;
    [self setNeedsFocusUpdate];
    [self updateFocusIfNeeded];
}

- (void)refreshToolbar {
    BrowserWebView *webView = self.tabCoordinator.activeWebView;
    BOOL startPage = [self showingStartPage];
    BOOL hasPage = webView.request.URL != nil;
    self.topBar.tabCount = self.tabCoordinator.tabCount;
    self.topBar.pageActionsEnabled = !startPage && hasPage;
    self.topBar.canGoBack = startPage ? hasPage : (webView.canGoBack || hasPage);
    self.topBar.canGoForward = webView.canGoForward;
    self.topBar.loading = !startPage && webView.isLoading;
    self.topBar.progress = webView.estimatedProgress;
    self.topBar.favorite = !startPage && [self browserCurrentPageIsFavorite];
    if (startPage) {
        [self.topBar setTitle:nil URLString:nil];
    } else {
        [self.topBar setTitle:webView.title URLString:webView.request.URL.absoluteString ?: self.tabCoordinator.activeTab.URLString];
    }
}

- (void)updatePageTint {
    BrowserWebView *webView = self.tabCoordinator.activeWebView;
    if (webView == nil || [self showingStartPage]) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    [webView fetchPageColorWithCompletion:^(UIColor *color) {
        if (webView != weakSelf.tabCoordinator.activeWebView) {
            return;
        }
        [UIView animateWithDuration:0.3 animations:^{
            weakSelf.view.backgroundColor = color ?: UIColor.blackColor;
        }];
    }];
}

- (NSArray<id<UIFocusEnvironment>> *)preferredFocusEnvironments {
    if ([self showingStartPage]) {
        return @[self.startPageView];
    }
    return @[];
}

#pragma mark Notifications

- (void)handleGlobalSelectPressEnded:(NSNotification *)notification {
    [self.inputController handleGlobalSelectPressEnded];
}

- (void)handleLibraryChange:(NSNotification *)notification {
    [self refreshToolbar];
}

#pragma mark Presses and touches

- (void)pressesBegan:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    if ([self.inputController handlePressesBegan:presses]) {
        return;
    }
    [super pressesBegan:presses withEvent:event];
}

- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    if ([self.inputController handlePressesEnded:presses]) {
        return;
    }
    [super pressesEnded:presses withEvent:event];
}

- (void)pressesCancelled:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    if ([self.inputController handlePressesCancelled:presses]) {
        return;
    }
    [super pressesCancelled:presses withEvent:event];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if ([self.inputController handleTouchesBegan:touches]) {
        return;
    }
    [super touchesBegan:touches withEvent:event];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if ([self.inputController handleTouchesMoved:touches]) {
        return;
    }
    [super touchesMoved:touches withEvent:event];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if ([self.inputController handleTouchesEnded:touches]) {
        return;
    }
    [super touchesEnded:touches withEvent:event];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if ([self.inputController handleTouchesEnded:touches]) {
        return;
    }
    [super touchesCancelled:touches withEvent:event];
}

#pragma mark Pointer geometry

- (BOOL)pointIsOnToolbar:(CGPoint)point {
    return [self toolbarVisible] && point.y < [BrowserTopBarView preferredHeight];
}

- (BOOL)webPoint:(CGPoint *)webPoint forPoint:(CGPoint)point {
    BrowserWebView *webView = self.tabCoordinator.activeWebView;
    if (webView == nil) {
        return NO;
    }
    CGPoint converted = [self.view convertPoint:point toView:webView];
    if (!CGRectContainsPoint(webView.bounds, converted)) {
        return NO;
    }
    *webPoint = converted;
    return YES;
}

#pragma mark BrowserRemoteInputControllerHost

- (BOOL)inputControllerPointerIsActive {
    return [self pointerActive];
}

- (UIScrollView *)inputControllerScrollView {
    return self.tabCoordinator.activeWebView.scrollView;
}

- (void)inputControllerCursorDidMoveToPoint:(CGPoint)point {
    if (![self toolbarPinned]) {
        if (!self.toolbarRevealed && point.y <= kToolbarRevealEdge) {
            self.toolbarRevealed = YES;
        } else if (self.toolbarRevealed && point.y > [BrowserTopBarView preferredHeight] + 90.0) {
            self.toolbarRevealed = NO;
        }
    }

    if ([self pointIsOnToolbar:point]) {
        BOOL hovering = [self.topBar updateHoverAtPoint:[self.view convertPoint:point toView:self.topBar]];
        [self.inputController setCursorIsOverInteractiveContent:hovering];
        return;
    }
    [self.topBar clearHover];

    CGPoint webPoint = CGPointZero;
    if (self.inputController.scrollModeEnabled || ![self webPoint:&webPoint forPoint:point]) {
        [self.inputController setCursorIsOverInteractiveContent:NO];
        return;
    }
    __weak typeof(self) weakSelf = self;
    [self.pageActionCoordinator hoverAtPoint:webPoint webView:self.tabCoordinator.activeWebView completion:^(BOOL interactive) {
        if ([weakSelf pointIsOnToolbar:weakSelf.inputController.cursorPoint]) {
            return;
        }
        [weakSelf.inputController setCursorIsOverInteractiveContent:interactive];
    }];
}

- (void)inputControllerDidClickAtPoint:(CGPoint)point {
    if ([self pointIsOnToolbar:point]) {
        [self.topBar activateAtPoint:[self.view convertPoint:point toView:self.topBar]];
        return;
    }
    CGPoint webPoint = CGPointZero;
    if ([self webPoint:&webPoint forPoint:point]) {
        [self.pageActionCoordinator clickAtPoint:webPoint webView:self.tabCoordinator.activeWebView];
    }
}

- (void)inputControllerDidHoldAtPoint:(CGPoint)point {
    CGPoint webPoint = CGPointZero;
    if ([self pointIsOnToolbar:point] || ![self webPoint:&webPoint forPoint:point]) {
        [self.menuCoordinator showMenu];
        return;
    }
    [self.pageActionCoordinator showActionsAtPoint:webPoint webView:self.tabCoordinator.activeWebView];
}

- (void)inputControllerScrollInnerContentAtPoint:(CGPoint)point delta:(CGPoint)delta {
    CGPoint webPoint = CGPointZero;
    if ([self webPoint:&webPoint forPoint:point]) {
        [self.pageActionCoordinator scrollInnerContentAtPoint:webPoint delta:delta webView:self.tabCoordinator.activeWebView];
    }
}

- (BOOL)inputControllerCanHandleMenuPress {
    if (self.tabCoordinator == nil || self.presentedViewController != nil) {
        return NO;
    }
    if ([self showingStartPage]) {
        // Back from the start page returns to the page under it; with no page, tvOS takes
        // the press and goes to the Home screen as usual.
        return self.tabCoordinator.activeWebView.request.URL != nil;
    }
    return YES;
}

- (void)inputControllerHandleMenuPress {
    if ([self showingStartPage]) {
        [self.tabCoordinator hideStartPageInActiveTab];
        return;
    }
    BrowserWebView *webView = self.tabCoordinator.activeWebView;
    if (webView.canGoBack) {
        [webView goBack];
    } else {
        [self.tabCoordinator showStartPageInActiveTab];
    }
}

- (void)inputControllerOpenMenu {
    [self.menuCoordinator showMenu];
}

- (void)inputControllerScrollModeDidChange:(BOOL)scrollModeEnabled {
    if (scrollModeEnabled) {
        [self.hudView showPersistentMessage:@"Scroll mode · swipe to scroll, click when done" symbolName:@"arrow.up.and.down"];
    } else {
        [self.hudView hide];
    }
}

- (void)inputControllerDidFinishScrolling {
    if (!self.inputController.scrollModeEnabled) {
        [self inputControllerCursorDidMoveToPoint:self.inputController.cursorPoint];
    }
}

#pragma mark BrowserTabCoordinatorHost

- (void)tabCoordinatorDidChangeActiveTab {
    BOOL startPage = [self showingStartPage];
    if (startPage) {
        [self.startPageView reloadContent];
        self.view.backgroundColor = UIColor.blackColor;
    } else {
        [self updatePageTint];
    }
    if (self.startPageView.hidden != !startPage) {
        self.startPageView.hidden = NO;
        self.startPageView.alpha = startPage ? 0.0 : 1.0;
        [BrowserTheme animate:^{
            self.startPageView.alpha = startPage ? 1.0 : 0.0;
        } completion:^{
            self.startPageView.hidden = ![self showingStartPage];
            self.startPageView.alpha = 1.0;
        }];
    }
    self.toolbarRevealed = NO;
    [BrowserTheme animate:^{
        [self layoutChrome];
    }];
    [self refreshToolbar];
    [self refreshPointerState];
    [self setNeedsFocusUpdate];
    [self updateFocusIfNeeded];
}

- (void)tabCoordinatorShowStatus:(NSString *)message symbolName:(NSString *)symbolName {
    [self browserShowStatus:message symbolName:symbolName];
}

#pragma mark BrowserWebViewDelegate

- (BOOL)isActive:(BrowserWebView *)webView {
    return webView == self.tabCoordinator.activeWebView;
}

- (BOOL)webView:(BrowserWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(NSInteger)navigationType {
    // A link straight to a video file goes to the player instead of WebKit's bare video page.
    if ([self isActive:webView] && [BrowserVideoPlaybackCoordinator URLLooksLikeMedia:request.URL]) {
        if ([self.videoCoordinator playMediaURLIfPossible:request.URL referrer:webView.request.URL.absoluteString title:nil]) {
            return NO;
        }
    }
    return YES;
}

- (BOOL)webView:(BrowserWebView *)webView shouldCreateNewTabWithRequest:(NSURLRequest *)request navigationType:(NSInteger)navigationType {
    if (request.URL == nil) {
        return NO;
    }
    return [self.tabCoordinator openNewTabWithRequest:request];
}

- (void)webViewDidStartLoad:(BrowserWebView *)webView {
    [self.videoCoordinator webViewDidNavigate:webView];
    if ([self isActive:webView]) {
        [self refreshToolbar];
    }
}

- (void)webViewDidFinishLoad:(BrowserWebView *)webView {
    [self.tabCoordinator webViewDidFinishLoad:webView];
    if ([self isActive:webView]) {
        [self refreshToolbar];
        [self updatePageTint];
    }
    BrowserTabViewModel *tab = [self.tabCoordinator tabForWebView:webView];
    NSUInteger tabIndex = tab != nil ? [self.viewModel.tabs indexOfObject:tab] : NSNotFound;
    if (tabIndex != NSNotFound) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.tabOverview reloadTabAtIndex:(NSInteger)tabIndex];
        });
    }
}

- (void)webViewDidUpdateState:(BrowserWebView *)webView {
    if ([self isActive:webView]) {
        [self refreshToolbar];
    }
}

- (void)webView:(BrowserWebView *)webView didFailLoadWithError:(NSError *)error {
    if (![self isActive:webView] || [self.navigationService shouldIgnoreLoadError:error] || [self showingStartPage]) {
        [self refreshToolbar];
        return;
    }
    [self refreshToolbar];
    NSURL *failingURL = error.userInfo[NSURLErrorFailingURLErrorKey];
    NSString *host = failingURL.host ?: @"the page";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Couldn’t Open %@", host]
                                                                   message:error.localizedDescription
                                                            preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    if (failingURL != nil) {
        UIAlertAction *retry = [UIAlertAction actionWithTitle:@"Try Again" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            NSURLRequest *request = [weakSelf.navigationService requestForURLString:failingURL.absoluteString];
            if (request != nil) {
                [webView loadRequest:request];
            }
        }];
        [alert addAction:retry];
        alert.preferredAction = retry;
        if (failingURL.host.length > 0) {
            [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"Search for “%@”", failingURL.host] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
                NSURLRequest *request = [weakSelf.navigationService searchRequestForQuery:failingURL.host];
                if (request != nil) {
                    [webView loadRequest:request];
                }
            }]];
        }
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]];
    [self browserPresentViewController:alert];
}

- (void)webView:(BrowserWebView *)webView didRequestFullscreenVideo:(NSDictionary *)info {
    if ([self isActive:webView] && !self.showingStartPage) {
        [self.videoCoordinator webView:webView didRequestFullscreenVideo:info];
    }
}

- (void)webView:(BrowserWebView *)webView didBlockPopupWithRequest:(NSURLRequest *)request {
    if ([self isActive:webView]) {
        [self.hudView showMessage:@"Pop-up blocked" symbolName:@"hand.raised.fill"];
    }
}

#pragma mark BrowserTopBarViewDelegate

- (void)browserTopBarView:(BrowserTopBarView *)topBarView didTriggerAction:(BrowserTopBarAction)action {
    BrowserWebView *webView = self.tabCoordinator.activeWebView;
    switch (action) {
        case BrowserTopBarActionBack:
            if ([self showingStartPage]) {
                [self.tabCoordinator hideStartPageInActiveTab];
            } else if (webView.canGoBack) {
                [webView goBack];
            } else {
                [self.tabCoordinator showStartPageInActiveTab];
            }
            break;
        case BrowserTopBarActionForward:
            if ([self showingStartPage]) {
                [self.tabCoordinator hideStartPageInActiveTab];
            }
            [webView goForward];
            break;
        case BrowserTopBarActionReload:
            if (webView.isLoading) {
                [webView stopLoading];
            } else {
                [webView reload];
            }
            break;
        case BrowserTopBarActionAddress:
            [self browserShowAddressEntry];
            break;
        case BrowserTopBarActionFavorite:
            [self browserToggleFavoriteForCurrentPage];
            break;
        case BrowserTopBarActionTabs:
            [self browserShowTabOverview];
            break;
        case BrowserTopBarActionMenu:
            [self.menuCoordinator showMenu];
            break;
    }
}

#pragma mark BrowserStartPageViewDelegate

- (void)startPageView:(BrowserStartPageView *)startPageView didSelectEntry:(BrowserLibraryEntry *)entry {
    [self browserLoadURLString:entry.URLString];
}

- (void)startPageView:(BrowserStartPageView *)startPageView didRequestActionsForEntry:(BrowserLibraryEntry *)entry isFavorite:(BOOL)isFavorite {
    [self.menuCoordinator showActionsForURLString:entry.URLString title:entry.title isFavorite:isFavorite];
}

#pragma mark BrowserTabOverviewControllerDelegate

- (void)tabOverviewController:(BrowserTabOverviewController *)controller didSelectTabAtIndex:(NSInteger)tabIndex {
    [self.tabCoordinator switchToTabAtIndex:tabIndex];
    [controller dismissViewControllerAnimated:YES completion:nil];
}

- (void)tabOverviewController:(BrowserTabOverviewController *)controller didCloseTabAtIndex:(NSInteger)tabIndex {
    [self.tabCoordinator closeTabAtIndex:tabIndex];
    [self refreshToolbar];
}

- (void)tabOverviewControllerDidRequestNewTab:(BrowserTabOverviewController *)controller {
    [controller dismissViewControllerAnimated:YES completion:^{
        [self browserOpenNewTab];
    }];
}

#pragma mark Shared host actions

- (BrowserWebView *)browserWebView {
    return self.tabCoordinator.activeWebView;
}

- (BOOL)browserShowingStartPage {
    return [self showingStartPage];
}

- (BOOL)browserNativeVideoPlayerEnabled {
    return self.preferencesStore.nativeVideoPlayerEnabled;
}

- (NSString *)browserUserAgent {
    return self.preferencesStore.userAgent;
}

- (void)browserPresentViewController:(UIViewController *)viewController {
    UIViewController *presenter = self;
    while (presenter.presentedViewController != nil && !presenter.presentedViewController.isBeingDismissed) {
        presenter = presenter.presentedViewController;
    }
    [self.inputController stopScrolling];
    [presenter presentViewController:viewController animated:YES completion:nil];
    [self refreshPointerState];
}

- (void)browserShowStatus:(NSString *)message symbolName:(NSString *)symbolName {
    [self.hudView showMessage:message symbolName:symbolName];
}

- (void)browserLoadRequest:(NSURLRequest *)request {
    if (request == nil) {
        return;
    }
    [self.tabCoordinator loadRequestInActiveTab:request];
    [self refreshToolbar];
}

- (void)browserLoadURLString:(NSString *)URLString {
    NSURL *URL = [NSURL URLWithString:URLString];
    if ([self.videoCoordinator playMediaURLIfPossible:URL referrer:nil title:nil]) {
        return;
    }
    [self browserLoadRequest:[self.navigationService requestForURLString:URLString]];
}

- (BOOL)browserOpenRequestInNewTab:(NSURLRequest *)request {
    return [self.tabCoordinator openNewTabWithRequest:request];
}

- (void)browserOpenURLStringInNewTab:(NSString *)URLString {
    NSURLRequest *request = [self.navigationService requestForURLString:URLString];
    if (request != nil) {
        [self.tabCoordinator openNewTabWithRequest:request];
    }
}

- (void)browserOpenNewTab {
    [self.tabCoordinator openNewTabWithRequest:[self.navigationService homePageRequest]];
}

- (void)browserShowStartPage {
    [self.tabCoordinator showStartPageInActiveTab];
}

- (void)browserOpenMenu {
    [self.menuCoordinator showMenu];
}

- (void)browserShowTabOverview {
    __weak typeof(self) weakSelf = self;
    [self.tabCoordinator captureSnapshotOfActiveTabWithCompletion:^{
        BrowserTabOverviewController *overview = [[BrowserTabOverviewController alloc] initWithViewModel:weakSelf.viewModel];
        overview.delegate = weakSelf;
        weakSelf.tabOverview = overview;
        [weakSelf browserPresentViewController:overview];
    }];
}

- (void)browserShowAddressEntry {
    BrowserWebView *webView = self.tabCoordinator.activeWebView;
    NSString *currentURLString = [self showingStartPage] ? @"" : (webView.request.URL.absoluteString ?: @"");
    NSString *engine = [BrowserPreferencesStore nameForSearchEngine:self.preferencesStore.searchEngine];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Search or Enter Website"
                                                                   message:[NSString stringWithFormat:@"Type an address, or words to search with %@.", engine]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.keyboardType = UIKeyboardTypeWebSearch;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.returnKeyType = UIReturnKeyGo;
        textField.placeholder = @"example.com or search words";
        textField.text = currentURLString;
        textField.clearButtonMode = UITextFieldViewModeAlways;
    }];
    __weak typeof(self) weakSelf = self;
    __weak typeof(alert) weakAlert = alert;
    UIAlertAction *go = [UIAlertAction actionWithTitle:@"Go" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSString *input = weakAlert.textFields.firstObject.text ?: @"";
        if ([input isEqualToString:currentURLString] && currentURLString.length > 0) {
            return;
        }
        NSURLRequest *request = [weakSelf.navigationService requestForUserInput:input];
        if (request == nil) {
            return;
        }
        if ([weakSelf.videoCoordinator playMediaURLIfPossible:request.URL referrer:nil title:nil]) {
            return;
        }
        [weakSelf browserLoadRequest:request];
    }];
    [alert addAction:go];
    alert.preferredAction = go;
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self browserPresentViewController:alert];
}

- (BOOL)browserCurrentPageIsFavorite {
    NSString *URLString = self.tabCoordinator.activeWebView.request.URL.absoluteString;
    return [[BrowserLibraryStore sharedStore] isFavoriteURLString:URLString ?: @""];
}

- (void)browserToggleFavoriteForCurrentPage {
    BrowserWebView *webView = self.tabCoordinator.activeWebView;
    NSString *URLString = webView.request.URL.absoluteString;
    if (URLString.length == 0 || [self showingStartPage]) {
        return;
    }
    BrowserLibraryStore *library = [BrowserLibraryStore sharedStore];
    if ([library isFavoriteURLString:URLString]) {
        [library removeFavoriteWithURLString:URLString];
        [self.hudView showMessage:@"Removed from Favorites" symbolName:@"star.slash"];
    } else {
        [library addFavoriteWithURLString:URLString title:webView.title];
        [self.hudView showMessage:@"Added to Favorites" symbolName:@"star.fill"];
    }
    [self refreshToolbar];
}

- (NSArray<BrowserMediaCandidate *> *)browserPlayableVideos {
    return [self.videoCoordinator playableCandidatesInWebView:self.tabCoordinator.activeWebView];
}

- (void)browserPlayVideo:(BrowserMediaCandidate *)candidate {
    [self.videoCoordinator playCandidate:candidate fromWebView:self.tabCoordinator.activeWebView];
}

- (void)browserPreferencesDidChange:(BrowserPreferenceChange)change {
    switch (change) {
        case BrowserPreferenceChangePageZoom:
            [self.tabCoordinator applyPageZoom:self.preferencesStore.pageZoomPercent / 100.0];
            break;
        case BrowserPreferenceChangeToolbar: {
            self.toolbarRevealed = NO;
            [BrowserTheme animate:^{
                [self layoutChrome];
            }];
            break;
        }
        case BrowserPreferenceChangeUserAgent:
            [self.tabCoordinator recreateAllWebViews];
            break;
        case BrowserPreferenceChangePopups:
            [self.tabCoordinator applyPopupBlocking:self.preferencesStore.blockPopups];
            break;
        case BrowserPreferenceChangeCursorSpeed:
            self.inputController.speedMultiplier = self.preferencesStore.cursorSpeedMultiplier;
            break;
        case BrowserPreferenceChangeContentBlocking:
            // Rule lists apply to the next load, so the current page is reloaded.
            [self.tabCoordinator.activeWebView reload];
            break;
    }
}

@end
