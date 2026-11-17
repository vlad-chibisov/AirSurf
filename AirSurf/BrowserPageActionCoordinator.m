#import "BrowserPageActionCoordinator.h"

#import "BrowserLibraryStore.h"
#import "BrowserNavigationService.h"
#import "BrowserPanelViewController.h"
#import "BrowserVideoPlaybackCoordinator.h"
#import "BrowserWebView.h"

static NSString *BrowserActionString(id value) {
    return [value isKindOfClass:[NSString class]] ? value : @"";
}

static BOOL BrowserActionBool(id value) {
    return [value respondsToSelector:@selector(boolValue)] && [value boolValue];
}

@interface BrowserPageActionCoordinator ()

@property (nonatomic, weak) id<BrowserPageActionCoordinatorHost> host;
@property (nonatomic) BrowserNavigationService *navigationService;
@property (nonatomic) BrowserVideoPlaybackCoordinator *videoPlaybackCoordinator;
@property (nonatomic) BOOL hoverInFlight;
@property (nonatomic) BOOL hasPendingHover;
@property (nonatomic) CGPoint pendingHoverPoint;
@property (nonatomic, weak) BrowserWebView *pendingHoverWebView;
@property (nonatomic, copy) void (^pendingHoverCompletion)(BOOL);

@end

@implementation BrowserPageActionCoordinator

- (instancetype)initWithHost:(id<BrowserPageActionCoordinatorHost>)host
           navigationService:(BrowserNavigationService *)navigationService
    videoPlaybackCoordinator:(BrowserVideoPlaybackCoordinator *)videoPlaybackCoordinator {
    self = [super init];
    if (self) {
        _host = host;
        _navigationService = navigationService;
        _videoPlaybackCoordinator = videoPlaybackCoordinator;
    }
    return self;
}

#pragma mark Hover

- (void)hoverAtPoint:(CGPoint)point webView:(BrowserWebView *)webView completion:(void (^)(BOOL))completion {
    if (self.hoverInFlight) {
        self.hasPendingHover = YES;
        self.pendingHoverPoint = point;
        self.pendingHoverWebView = webView;
        self.pendingHoverCompletion = completion;
        return;
    }
    self.hoverInFlight = YES;
    __weak typeof(self) weakSelf = self;
    [webView performPointCommand:@"hover" atPoint:point data:nil completion:^(NSDictionary *result) {
        typeof(self) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        strongSelf.hoverInFlight = NO;
        if (strongSelf.hasPendingHover) {
            // The cursor has moved on; answer for where it is now instead.
            strongSelf.hasPendingHover = NO;
            BrowserWebView *nextWebView = strongSelf.pendingHoverWebView;
            void (^nextCompletion)(BOOL) = strongSelf.pendingHoverCompletion;
            strongSelf.pendingHoverCompletion = nil;
            if (nextWebView != nil && nextCompletion != nil) {
                [strongSelf hoverAtPoint:strongSelf.pendingHoverPoint webView:nextWebView completion:nextCompletion];
            }
            return;
        }
        completion(BrowserActionBool(result[@"interactive"]));
    }];
}

#pragma mark Click

- (void)clickAtPoint:(CGPoint)point webView:(BrowserWebView *)webView {
    __weak typeof(self) weakSelf = self;
    [webView performPointCommand:@"click" atPoint:point data:nil completion:^(NSDictionary *result) {
        typeof(self) strongSelf = weakSelf;
        if (strongSelf == nil || result == nil) {
            return;
        }
        NSString *action = BrowserActionString(result[@"action"]);
        if ([action isEqualToString:@"edit"]) {
            NSDictionary *editable = [result[@"editable"] isKindOfClass:[NSDictionary class]] ? result[@"editable"] : @{};
            if ([BrowserActionString(editable[@"kind"]) isEqualToString:@"select"]) {
                [strongSelf presentOptionsForSelect:editable point:point webView:webView];
            } else {
                [strongSelf presentTextEntryForField:editable point:point webView:webView];
            }
            return;
        }
        if ([action isEqualToString:@"newtab"]) {
            NSDictionary *link = [result[@"link"] isKindOfClass:[NSDictionary class]] ? result[@"link"] : @{};
            [strongSelf openURLString:BrowserActionString(link[@"href"]) inNewTab:YES];
            return;
        }
        [strongSelf.videoPlaybackCoordinator noteClickResult:result inWebView:webView];
    }];
}

- (void)openURLString:(NSString *)URLString inNewTab:(BOOL)inNewTab {
    NSURL *URL = [NSURL URLWithString:URLString];
    if (URL == nil) {
        return;
    }
    if ([self.videoPlaybackCoordinator playMediaURLIfPossible:URL referrer:nil title:nil]) {
        return;
    }
    NSURLRequest *request = [self.navigationService requestForURLString:URLString];
    if (request == nil) {
        return;
    }
    if (inNewTab) {
        [self.host browserOpenRequestInNewTab:request];
    } else {
        [self.host browserLoadRequest:request];
    }
}

#pragma mark Text entry

- (UIKeyboardType)keyboardTypeForFieldType:(NSString *)fieldType {
    if ([fieldType isEqualToString:@"url"]) {
        return UIKeyboardTypeURL;
    }
    if ([fieldType isEqualToString:@"email"]) {
        return UIKeyboardTypeEmailAddress;
    }
    if ([@[@"tel", @"number", @"date", @"datetime", @"datetime-local", @"month", @"time", @"week"] containsObject:fieldType]) {
        return UIKeyboardTypeNumbersAndPunctuation;
    }
    return UIKeyboardTypeDefault;
}

- (void)presentTextEntryForField:(NSDictionary *)field point:(CGPoint)point webView:(BrowserWebView *)webView {
    NSString *fieldType = BrowserActionString(field[@"type"]);
    NSString *label = BrowserActionString(field[@"label"]);
    NSString *placeholder = BrowserActionString(field[@"placeholder"]);
    BOOL isSearch = [fieldType isEqualToString:@"search"] ||
        [[label stringByAppendingString:placeholder].lowercaseString rangeOfString:@"search"].location != NSNotFound ||
        [[label stringByAppendingString:placeholder].lowercaseString rangeOfString:@"поиск"].location != NSNotFound;
    BOOL canSubmit = BrowserActionBool(field[@"hasForm"]) || isSearch;
    BOOL multiline = BrowserActionBool(field[@"multiline"]);

    NSString *title = label.length > 0 ? label : (isSearch ? @"Search" : @"Enter Text");
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.keyboardType = [self keyboardTypeForFieldType:fieldType];
        textField.placeholder = placeholder.length > 0 ? placeholder : title;
        textField.secureTextEntry = [fieldType isEqualToString:@"password"];
        textField.text = BrowserActionString(field[@"value"]);
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.returnKeyType = canSubmit ? (isSearch ? UIReturnKeySearch : UIReturnKeyGo) : UIReturnKeyDone;
    }];

    __weak typeof(alert) weakAlert = alert;
    void (^commit)(BOOL) = ^(BOOL submit) {
        NSString *text = weakAlert.textFields.firstObject.text ?: @"";
        [webView performPointCommand:@"setText" atPoint:point data:@{ @"text": text, @"submit": @(submit) } completion:nil];
    };
    if (canSubmit && !multiline) {
        UIAlertAction *submitAction = [UIAlertAction actionWithTitle:isSearch ? @"Search" : @"Submit" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            commit(YES);
        }];
        [alert addAction:submitAction];
        alert.preferredAction = submitAction;
        [alert addAction:[UIAlertAction actionWithTitle:@"Fill In Only" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            commit(NO);
        }]];
    } else {
        UIAlertAction *doneAction = [UIAlertAction actionWithTitle:@"Done" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            commit(NO);
        }];
        [alert addAction:doneAction];
        alert.preferredAction = doneAction;
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self.host browserPresentViewController:alert];
}

- (void)presentOptionsForSelect:(NSDictionary *)field point:(CGPoint)point webView:(BrowserWebView *)webView {
    NSArray *options = [field[@"options"] isKindOfClass:[NSArray class]] ? field[@"options"] : @[];
    NSMutableArray<BrowserPanelItem *> *items = [NSMutableArray array];
    for (NSDictionary *option in options) {
        if (![option isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSNumber *index = [option[@"index"] isKindOfClass:[NSNumber class]] ? option[@"index"] : @0;
        NSString *text = BrowserActionString(option[@"text"]);
        BrowserPanelItem *item = [BrowserPanelItem itemWithTitle:text.length > 0 ? text : @"—" symbolName:nil handler:^{
            [webView performPointCommand:@"setSelect" atPoint:point data:@{ @"index": index } completion:nil];
        }];
        item.checked = BrowserActionBool(option[@"selected"]);
        item.enabled = !BrowserActionBool(option[@"disabled"]);
        [items addObject:item];
    }
    BrowserPanelPage *page = [BrowserPanelPage pageWithTitle:@"Choose" sections:^NSArray<BrowserPanelSection *> *{
        return @[[BrowserPanelSection sectionWithTitle:nil items:items]];
    }];
    page.emptyMessage = @"This list has no options.";
    [self.host browserPresentViewController:[[BrowserPanelViewController alloc] initWithRootPage:page]];
}

#pragma mark Hold

- (void)showActionsAtPoint:(CGPoint)point webView:(BrowserWebView *)webView {
    __weak typeof(self) weakSelf = self;
    [webView performPointCommand:@"context" atPoint:point data:nil completion:^(NSDictionary *result) {
        typeof(self) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        [strongSelf presentActionsForResult:result ?: @{} webView:webView];
    }];
}

- (void)presentActionsForResult:(NSDictionary *)result webView:(BrowserWebView *)webView {
    __weak typeof(self) weakSelf = self;
    NSMutableArray<BrowserPanelSection *> *sections = [NSMutableArray array];

    NSDictionary *link = [result[@"link"] isKindOfClass:[NSDictionary class]] ? result[@"link"] : nil;
    NSString *href = BrowserActionString(link[@"href"]);
    NSURL *linkURL = href.length > 0 ? [NSURL URLWithString:href] : nil;
    BOOL linkIsWeb = linkURL != nil && ([linkURL.scheme.lowercaseString isEqualToString:@"http"] || [linkURL.scheme.lowercaseString isEqualToString:@"https"]);
    if (linkIsWeb && !BrowserActionBool(link[@"script"])) {
        NSString *linkText = BrowserActionString(link[@"text"]);
        NSMutableArray<BrowserPanelItem *> *linkItems = [NSMutableArray array];
        BrowserPanelItem *openItem = [BrowserPanelItem itemWithTitle:@"Open Link" symbolName:@"arrow.up.right" handler:^{
            [weakSelf openURLString:href inNewTab:NO];
        }];
        openItem.subtitle = href;
        [linkItems addObject:openItem];
        [linkItems addObject:[BrowserPanelItem itemWithTitle:@"Open in New Tab" symbolName:@"plus.square.on.square" handler:^{
            [weakSelf openURLString:href inNewTab:YES];
        }]];
        if (![[BrowserLibraryStore sharedStore] isFavoriteURLString:href]) {
            [linkItems addObject:[BrowserPanelItem itemWithTitle:@"Add Link to Favorites" symbolName:@"star" handler:^{
                [[BrowserLibraryStore sharedStore] addFavoriteWithURLString:href title:linkText];
                [weakSelf.host browserShowStatus:@"Added to Favorites" symbolName:@"star.fill"];
            }]];
        }
        [sections addObject:[BrowserPanelSection sectionWithTitle:@"Link" items:linkItems]];
    }

    NSArray<BrowserMediaCandidate *> *candidates = [self.videoPlaybackCoordinator playableCandidatesInWebView:webView];
    if (candidates.count > 0) {
        NSMutableArray<BrowserPanelItem *> *videoItems = [NSMutableArray array];
        BrowserMediaCandidate *best = candidates.firstObject;
        BrowserPanelItem *playItem = [BrowserPanelItem itemWithTitle:@"Play Video Full Screen" symbolName:@"play.rectangle.fill" handler:^{
            [weakSelf.videoPlaybackCoordinator playCandidate:best fromWebView:webView];
        }];
        playItem.subtitle = [NSString stringWithFormat:@"%@ · %@", best.displayName, best.URL.host ?: @""];
        [videoItems addObject:playItem];
        [sections addObject:[BrowserPanelSection sectionWithTitle:@"Video" items:videoItems]];
    }

    BOOL isFavorite = [self.host browserCurrentPageIsFavorite];
    NSArray<BrowserPanelItem *> *pageItems = @[
        [BrowserPanelItem itemWithTitle:@"Reload Page" symbolName:@"arrow.clockwise" handler:^{
            [webView reload];
        }],
        [BrowserPanelItem itemWithTitle:isFavorite ? @"Remove Page from Favorites" : @"Add Page to Favorites"
                             symbolName:isFavorite ? @"star.slash" : @"star"
                                handler:^{
            [weakSelf.host browserToggleFavoriteForCurrentPage];
        }],
        [BrowserPanelItem itemWithTitle:@"Menu" symbolName:@"ellipsis.circle" handler:^{
            [weakSelf.host browserOpenMenu];
        }],
    ];
    [sections addObject:[BrowserPanelSection sectionWithTitle:@"Page" items:pageItems]];

    BrowserPanelPage *page = [BrowserPanelPage pageWithTitle:@"Actions" sections:^NSArray<BrowserPanelSection *> *{
        return sections;
    }];
    [self.host browserPresentViewController:[[BrowserPanelViewController alloc] initWithRootPage:page]];
}

#pragma mark Scroll

- (void)scrollInnerContentAtPoint:(CGPoint)point delta:(CGPoint)delta webView:(BrowserWebView *)webView {
    CGFloat viewWidth = CGRectGetWidth(webView.bounds);
    CGFloat scale = 1.0;
    if (viewWidth > 0.0 && webView.pageZoom > 0.0) {
        scale = 1.0 / webView.pageZoom;
    }
    [webView performPointCommand:@"scroll" atPoint:point data:@{ @"dx": @(delta.x * scale), @"dy": @(delta.y * scale) } completion:nil];
}

@end
