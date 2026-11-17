#import "BrowserWebView.h"

#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "BrowserWebKitInterfaces.h"

// WebKit is not in the public tvOS SDK. Its classes are looked up by name once the framework
// is loaded; calls go through the protocols in BrowserWebKitInterfaces.h, or through
// objc_msgSend for the handful of private methods.

static NSString * const kAgentMessageHandlerName = @"tvb";
static NSString * const kContentBlockingDefaultsKey = @"BlockAds";

#pragma mark - Runtime helpers

extern void BrowserInstallPrivacyStanceFallback(void);

/// Loads WebKit into the process if nothing has yet. Safe to call repeatedly.
static BOOL BrowserLoadWebKit(void) {
    static BOOL loaded;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        loaded = NSClassFromString(@"WKWebView") != Nil;
        // tvOS has carried the framework in different places over the years.
        const char *locations[] = {
            "/System/Library/Frameworks/WebKit.framework/WebKit",
            "/System/Library/PrivateFrameworks/WebKit.framework/WebKit",
        };
        for (size_t i = 0; !loaded && i < sizeof(locations) / sizeof(locations[0]); i++) {
            loaded = dlopen(locations[i], RTLD_NOW) != NULL && NSClassFromString(@"WKWebView") != Nil;
        }
        if (loaded) {
            BrowserInstallPrivacyStanceFallback();
        }
    });
    return loaded;
}

/// Starts some asynchronous WebKit work and keeps the main run loop turning until it calls
/// `finish` or `timeout` passes. Only for the few places that need an answer right away
/// (saving cookies as the app is suspended, restoring them before the first page loads).
static void BrowserWaitForWork(NSTimeInterval timeout, void (^work)(dispatch_block_t finish)) {
    __block BOOL finished = NO;
    work(^{ finished = YES; });
    CFAbsoluteTime giveUp = CFAbsoluteTimeGetCurrent() + timeout;
    while (!finished && CFAbsoluteTimeGetCurrent() < giveUp) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, true);
    }
}

static id BrowserObject(id target, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    if (target == nil || ![target respondsToSelector:selector]) {
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(target, selector);
}

static BOOL BrowserBool(id target, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    if (target == nil || ![target respondsToSelector:selector]) {
        return NO;
    }
    return ((BOOL (*)(id, SEL))objc_msgSend)(target, selector);
}

static void BrowserSetBool(id target, NSString *selectorName, BOOL value) {
    SEL selector = NSSelectorFromString(selectorName);
    if (target != nil && [target respondsToSelector:selector]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(target, selector, value);
    }
}

static void BrowserSetObject(id target, NSString *selectorName, id value) {
    SEL selector = NSSelectorFromString(selectorName);
    if (target != nil && [target respondsToSelector:selector]) {
        ((void (*)(id, SEL, id))objc_msgSend)(target, selector, value);
    }
}

static NSString *BrowserString(id value) {
    return [value isKindOfClass:[NSString class]] ? value : @"";
}

/// A script's return value as text; nil for undefined/null.
static NSString *BrowserJavaScriptString(id value) {
    if ([value isKindOfClass:[NSString class]]) {
        return value;
    }
    if (value == nil || [value isKindOfClass:[NSNull class]]) {
        return nil;
    }
    return [value isKindOfClass:[NSNumber class]] ? [value stringValue] : [value description];
}

static NSString *BrowserJSONLiteral(id object) {
    if (object == nil) {
        return @"null";
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:@[object] options:0 error:nil];
    if (data == nil) {
        return @"null";
    }
    NSString *wrapped = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    // Strip the wrapping array brackets; also keep the literal safe inside a <script>-less JS string.
    NSString *literal = [wrapped substringWithRange:NSMakeRange(1, wrapped.length - 2)];
    literal = [literal stringByReplacingOccurrencesOfString:@" " withString:@"\\u2028"];
    literal = [literal stringByReplacingOccurrencesOfString:@" " withString:@"\\u2029"];
    return literal;
}

static UIColor *BrowserColorFromCSSString(NSString *string) {
    NSString *value = [[string lowercaseString] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (value.length == 0) {
        return nil;
    }
    if ([value hasPrefix:@"#"]) {
        NSString *hex = [value substringFromIndex:1];
        if (hex.length == 3 || hex.length == 4) {
            NSMutableString *expanded = [NSMutableString string];
            for (NSUInteger index = 0; index < hex.length; index += 1) {
                NSString *character = [hex substringWithRange:NSMakeRange(index, 1)];
                [expanded appendFormat:@"%@%@", character, character];
            }
            hex = expanded;
        }
        if (hex.length != 6 && hex.length != 8) {
            return nil;
        }
        unsigned int rgba = 0;
        if (![[NSScanner scannerWithString:hex] scanHexInt:&rgba]) {
            return nil;
        }
        if (hex.length == 6) {
            rgba = (rgba << 8) | 0xFF;
        }
        return [UIColor colorWithRed:((rgba >> 24) & 0xFF) / 255.0
                               green:((rgba >> 16) & 0xFF) / 255.0
                                blue:((rgba >> 8) & 0xFF) / 255.0
                               alpha:1.0];
    }
    if ([value hasPrefix:@"rgb"]) {
        NSRange open = [value rangeOfString:@"("];
        NSRange close = [value rangeOfString:@")" options:NSBackwardsSearch];
        if (open.location == NSNotFound || close.location == NSNotFound || close.location <= open.location) {
            return nil;
        }
        NSString *inner = [value substringWithRange:NSMakeRange(open.location + 1, close.location - open.location - 1)];
        inner = [inner stringByReplacingOccurrencesOfString:@"/" withString:@" "];
        inner = [inner stringByReplacingOccurrencesOfString:@"," withString:@" "];
        NSMutableArray<NSNumber *> *components = [NSMutableArray array];
        for (NSString *part in [inner componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet]) {
            if (part.length > 0) {
                [components addObject:@(part.doubleValue)];
            }
        }
        if (components.count < 3) {
            return nil;
        }
        if (components.count >= 4 && components[3].doubleValue < 0.5) {
            return nil;
        }
        return [UIColor colorWithRed:components[0].doubleValue / 255.0
                               green:components[1].doubleValue / 255.0
                                blue:components[2].doubleValue / 255.0
                               alpha:1.0];
    }
    return nil;
}

#pragma mark - BrowserMediaCandidate

@interface BrowserMediaCandidate ()

@property (nonatomic, strong, readwrite) NSURL *URL;
@property (nonatomic, readwrite) BrowserMediaKind kind;
@property (nonatomic, copy, readwrite) NSString *frameURLString;
@property (nonatomic, readwrite) BOOL fromMainFrame;
@property (nonatomic, readwrite) BOOL fromElement;
@property (nonatomic, readwrite) BOOL isMasterPlaylist;
@property (nonatomic, readwrite) BOOL isMediaPlaylist;
@property (nonatomic, readwrite) BOOL muted;
@property (nonatomic, readwrite) BOOL loops;
@property (nonatomic, readwrite) BOOL started;
@property (nonatomic, readwrite) CGSize elementSize;
@property (nonatomic, readwrite) NSTimeInterval duration;
@property (nonatomic, strong, readwrite) NSDate *firstSeen;
@property (nonatomic, copy, readwrite) NSString *pageTitle;

@end

@implementation BrowserMediaCandidate

- (void)updateFromDictionary:(NSDictionary *)dictionary {
    NSString *kind = BrowserString(dictionary[@"kind"]);
    if ([kind isEqualToString:@"hls"]) {
        self.kind = BrowserMediaKindHLS;
    } else if ([kind isEqualToString:@"file"]) {
        self.kind = BrowserMediaKindFile;
    } else {
        self.kind = BrowserMediaKindUnsupported;
    }
    if ([dictionary[@"element"] respondsToSelector:@selector(boolValue)] && [dictionary[@"element"] boolValue]) {
        self.fromElement = YES;
    }
    if ([dictionary[@"master"] respondsToSelector:@selector(boolValue)]) {
        self.isMasterPlaylist = [dictionary[@"master"] boolValue];
    }
    if ([dictionary[@"playlist"] respondsToSelector:@selector(boolValue)]) {
        self.isMediaPlaylist = [dictionary[@"playlist"] boolValue];
    }
    if ([dictionary[@"muted"] respondsToSelector:@selector(boolValue)]) {
        self.muted = [dictionary[@"muted"] boolValue];
    }
    if ([dictionary[@"loop"] respondsToSelector:@selector(boolValue)]) {
        self.loops = [dictionary[@"loop"] boolValue];
    }
    if ([dictionary[@"started"] respondsToSelector:@selector(boolValue)] && [dictionary[@"started"] boolValue]) {
        self.started = YES;
    }
    if ([dictionary[@"duration"] respondsToSelector:@selector(doubleValue)]) {
        self.duration = [dictionary[@"duration"] doubleValue];
    }
    if ([dictionary[@"width"] respondsToSelector:@selector(doubleValue)] &&
        [dictionary[@"height"] respondsToSelector:@selector(doubleValue)]) {
        self.elementSize = CGSizeMake([dictionary[@"width"] doubleValue], [dictionary[@"height"] doubleValue]);
    }
}

- (BOOL)isPlayableNatively {
    return self.kind != BrowserMediaKindUnsupported;
}

- (NSString *)displayName {
    NSString *kindName = @"Video";
    if (self.kind == BrowserMediaKindHLS) {
        kindName = self.isMasterPlaylist ? @"HLS stream (all qualities)" : @"HLS stream";
    } else if (self.kind == BrowserMediaKindFile) {
        kindName = [NSString stringWithFormat:@"%@ file", self.URL.pathExtension.length > 0 ? self.URL.pathExtension.uppercaseString : @"Video"];
    } else {
        kindName = @"Unsupported stream";
    }
    return kindName;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<Media %@ %@ frame=%@ element=%d master=%d>",
            self.displayName, self.URL.absoluteString, self.frameURLString, self.fromElement, self.isMasterPlaylist];
}

@end

#pragma mark - BrowserWebView private interface

@interface BrowserWebView ()

/// The real WKWebView, filling this view.
@property (nullable, nonatomic, strong) UIView<BrowserWKWebView> *runtimeWebView;
/// What the page was last known to be, for while WebKit reports nothing (mid-navigation, after a crash).
@property (nullable, nonatomic, strong) NSURLRequest *lastRequest;
@property (nullable, nonatomic, copy) NSString *lastTitle;
@property (nonatomic, copy) NSString *userAgent;
@property (nonatomic) BOOL loading;
@property (nonatomic) BOOL observingRuntimeWebView;
@property (nonatomic) BOOL stateUpdateScheduled;
@property (nonatomic) NSUInteger blockedRequestCount;
@property (nonatomic) NSMutableDictionary<NSString *, BrowserMediaCandidate *> *candidatesByURL;
@property (nonatomic) NSMutableArray<BrowserMediaCandidate *> *orderedCandidates;
@property (nonatomic) NSMutableDictionary<NSNumber *, void (^)(NSDictionary * _Nullable)> *pendingPointCompletions;
@property (nonatomic) NSUInteger nextPointCommandIdentifier;
@property (nonatomic) NSUInteger processTerminationCount;

- (void)handleAgentMessage:(NSDictionary *)message fromMainFrame:(BOOL)fromMainFrame;

@end

#pragma mark - BrowserWebEnvironment

@interface BrowserWebEnvironment ()

@property (nonatomic, readwrite, nullable) id userContentController;
@property (nonatomic, readwrite) NSString *agentToken;
@property (nonatomic) NSMapTable<id, BrowserWebView *> *webViewsByRuntimeView;
@property (nonatomic) NSMutableArray *compiledRuleLists;
@property (nonatomic) BOOL ruleListsAttached;
@property (nonatomic) BOOL ruleListsPreparing;
@property (nonatomic, readwrite) NSUInteger contentRuleCount;
@property (nonatomic, readwrite) BOOL contentBlockingAvailable;
@property (nonatomic, readwrite, nullable) NSString *contentBlockingFailureReason;
@property (nonatomic) NSMutableArray<void (^)(void)> *readyBlocks;

@end

@implementation BrowserWebEnvironment

+ (instancetype)sharedEnvironment {
    static BrowserWebEnvironment *environment;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        environment = [BrowserWebEnvironment new];
    });
    return environment;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        BrowserLoadWebKit();
        _agentToken = [[[NSUUID UUID] UUIDString] stringByReplacingOccurrencesOfString:@"-" withString:@""];
        _webViewsByRuntimeView = [NSMapTable weakToWeakObjectsMapTable];
        _compiledRuleLists = [NSMutableArray array];
        NSNumber *storedPreference = [[NSUserDefaults standardUserDefaults] objectForKey:kContentBlockingDefaultsKey];
        _contentBlockingEnabled = storedPreference != nil ? storedPreference.boolValue : YES;
        [self buildUserContentController];
        [self prepareContentRuleLists];
    }
    return self;
}

- (void)buildUserContentController {
    Class controllerClass = NSClassFromString(@"WKUserContentController");
    Class userScriptClass = NSClassFromString(@"WKUserScript");
    if (controllerClass == Nil) {
        return;
    }
    id controller = [controllerClass new];
    self.userContentController = controller;

    NSString *agentPath = [[NSBundle mainBundle] pathForResource:@"BrowserAgent" ofType:@"js"];
    NSString *agentSource = agentPath != nil ? [NSString stringWithContentsOfFile:agentPath encoding:NSUTF8StringEncoding error:nil] : nil;
    SEL scriptInitializer = NSSelectorFromString(@"initWithSource:injectionTime:forMainFrameOnly:");
    if (agentSource.length > 0 && userScriptClass != Nil && [userScriptClass instancesRespondToSelector:scriptInitializer]) {
        agentSource = [agentSource stringByReplacingOccurrencesOfString:@"__TVB_TOKEN__" withString:self.agentToken];
        id userScript = ((id (*)(id, SEL, id, NSInteger, BOOL))objc_msgSend)([userScriptClass alloc], scriptInitializer, agentSource, 0, NO);
        BrowserSetObject(controller, @"addUserScript:", userScript);
    } else {
        NSLog(@"[Browser] Page agent script missing; video detection and iframe clicks are disabled.");
    }

    SEL addHandlerSelector = NSSelectorFromString(@"addScriptMessageHandler:name:");
    if ([controller respondsToSelector:addHandlerSelector]) {
        ((void (*)(id, SEL, id, id))objc_msgSend)(controller, addHandlerSelector, self, kAgentMessageHandlerName);
    }
}

- (void)registerWebView:(BrowserWebView *)webView forRuntimeView:(id)runtimeView {
    if (webView != nil && runtimeView != nil) {
        [self.webViewsByRuntimeView setObject:webView forKey:runtimeView];
    }
}

// WKScriptMessageHandler
- (void)userContentController:(id)userContentController didReceiveScriptMessage:(id)message {
    (void)userContentController;
    id body = BrowserObject(message, @"body");
    if (![body isKindOfClass:[NSDictionary class]]) {
        return;
    }
    id runtimeView = BrowserObject(message, @"webView");
    BrowserWebView *webView = runtimeView != nil ? [self.webViewsByRuntimeView objectForKey:runtimeView] : nil;
    if (webView == nil) {
        return;
    }
    id frameInfo = BrowserObject(message, @"frameInfo");
    BOOL fromMainFrame = frameInfo != nil ? BrowserBool(frameInfo, @"isMainFrame") : YES;
    [webView handleAgentMessage:body fromMainFrame:fromMainFrame];
}

#pragma mark Content blocking

- (id)ruleListStore {
    Class storeClass = NSClassFromString(@"WKContentRuleListStore");
    if (storeClass == Nil) {
        return nil;
    }
    // On Apple TV hardware an app may only write to Caches; the default store lives in
    // Library/WebKit and compiling into it fails. Caches can be purged, which only means
    // a recompile (well under a second) on the next launch.
    SEL storeWithURLSelector = NSSelectorFromString(@"storeWithURL:");
    if ([storeClass respondsToSelector:storeWithURLSelector]) {
        NSURL *caches = [[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
        NSURL *directory = [caches URLByAppendingPathComponent:@"ContentRuleLists" isDirectory:YES];
        [[NSFileManager defaultManager] createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil];
        id store = ((id (*)(id, SEL, id))objc_msgSend)((id)storeClass, storeWithURLSelector, directory);
        if (store != nil) {
            return store;
        }
    }
    SEL defaultStoreSelector = NSSelectorFromString(@"defaultStore");
    if (![storeClass respondsToSelector:defaultStoreSelector]) {
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)((id)storeClass, defaultStoreSelector);
}

- (void)prepareContentRuleLists {
    id store = [self ruleListStore];
    NSArray<NSURL *> *ruleFiles = [[NSBundle mainBundle] URLsForResourcesWithExtension:@"json" subdirectory:nil];
    NSMutableArray<NSURL *> *contentRuleFiles = [NSMutableArray array];
    for (NSURL *ruleFile in ruleFiles) {
        if ([ruleFile.lastPathComponent hasPrefix:@"ContentRules"]) {
            [contentRuleFiles addObject:ruleFile];
        }
    }
    [contentRuleFiles sortUsingComparator:^NSComparisonResult(NSURL *first, NSURL *second) {
        return [first.lastPathComponent compare:second.lastPathComponent];
    }];

    SEL lookupSelector = NSSelectorFromString(@"lookUpContentRuleListForIdentifier:completionHandler:");
    SEL compileSelector = NSSelectorFromString(@"compileContentRuleListForIdentifier:encodedContentRuleList:completionHandler:");
    NSString *missing = nil;
    if (store == nil) {
        missing = NSClassFromString(@"WKContentRuleListStore") == Nil ? @"WebKit has no content blocker" : @"No rule store";
    } else if (contentRuleFiles.count == 0) {
        missing = @"Rule list missing from the app";
    } else if (![store respondsToSelector:lookupSelector] || ![store respondsToSelector:compileSelector]) {
        missing = @"Rule store API missing";
    } else if (![self.userContentController respondsToSelector:NSSelectorFromString(@"addContentRuleList:")]) {
        missing = @"Rule lists cannot be attached";
    }
    if (missing != nil) {
        self.contentBlockingAvailable = NO;
        self.contentBlockingFailureReason = missing;
        NSLog(@"[Browser] Content blocking unavailable: %@", missing);
        return;
    }

    self.contentBlockingAvailable = YES;
    self.ruleListsPreparing = YES;
    NSString *bundleVersion = NSBundle.mainBundle.infoDictionary[@"CFBundleVersion"] ?: @"0";
    dispatch_group_t group = dispatch_group_create();
    __weak typeof(self) weakSelf = self;

    for (NSURL *ruleFile in contentRuleFiles) {
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:ruleFile.path error:nil];
        NSString *identifier = [NSString stringWithFormat:@"tvb.%@.%@.%llu",
                                ruleFile.lastPathComponent.stringByDeletingPathExtension,
                                bundleVersion,
                                [attributes fileSize]];
        dispatch_group_enter(group);
        void (^finish)(id, NSError *) = ^(id ruleList, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (ruleList != nil) {
                    [weakSelf.compiledRuleLists addObject:ruleList];
                } else {
                    NSLog(@"[Browser] Content rule list %@ failed: %@", identifier, error);
                    weakSelf.contentBlockingFailureReason = error.localizedDescription ?: @"The rule list could not be compiled";
                }
                dispatch_group_leave(group);
            });
        };
        ((void (*)(id, SEL, id, id))objc_msgSend)(store, lookupSelector, identifier, ^(id existingList, NSError *lookupError) {
            (void)lookupError;
            if (existingList != nil) {
                NSLog(@"[Browser] Content rule list %@ loaded from store", identifier);
                finish(existingList, nil);
                return;
            }
            NSLog(@"[Browser] Compiling content rule list %@", identifier);
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                NSError *readError = nil;
                NSString *encodedRules = [NSString stringWithContentsOfURL:ruleFile encoding:NSUTF8StringEncoding error:&readError];
                if (encodedRules.length == 0) {
                    finish(nil, readError ?: [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError
                                                             userInfo:@{NSLocalizedDescriptionKey: @"The rule list could not be read"}]);
                    return;
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    ((void (*)(id, SEL, id, id, id))objc_msgSend)(store, compileSelector, identifier, encodedRules, ^(id compiledList, NSError *compileError) {
                        finish(compiledList, compileError);
                    });
                });
            });
        });
    }

    NSURL *countFile = [[NSBundle mainBundle] URLForResource:@"ContentRulesInfo" withExtension:@"plist"];
    NSDictionary *info = countFile != nil ? [NSDictionary dictionaryWithContentsOfURL:countFile] : nil;
    self.contentRuleCount = [info[@"ruleCount"] unsignedIntegerValue];

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        weakSelf.ruleListsPreparing = NO;
        if (weakSelf.compiledRuleLists.count == 0) {
            weakSelf.contentBlockingAvailable = NO;
        }
        [weakSelf syncRuleListAttachment];
        [weakSelf flushReadyBlocks];
    });
}

- (void)performWhenContentBlockingReady:(void (^)(void))block timeout:(NSTimeInterval)timeout {
    if (!self.ruleListsPreparing) {
        block();
        return;
    }
    if (self.readyBlocks == nil) {
        self.readyBlocks = [NSMutableArray array];
    }
    [self.readyBlocks addObject:[block copy]];
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf flushReadyBlocks];
    });
}

- (void)flushReadyBlocks {
    NSArray<void (^)(void)> *blocks = [self.readyBlocks copy];
    [self.readyBlocks removeAllObjects];
    for (void (^block)(void) in blocks) {
        block();
    }
}

- (void)syncRuleListAttachment {
    BOOL shouldAttach = self.contentBlockingEnabled && self.compiledRuleLists.count > 0;
    if (shouldAttach == self.ruleListsAttached) {
        return;
    }
    id controller = self.userContentController;
    for (id ruleList in self.compiledRuleLists) {
        BrowserSetObject(controller, shouldAttach ? @"addContentRuleList:" : @"removeContentRuleList:", ruleList);
    }
    self.ruleListsAttached = shouldAttach;
}

- (void)setContentBlockingEnabled:(BOOL)contentBlockingEnabled {
    _contentBlockingEnabled = contentBlockingEnabled;
    [[NSUserDefaults standardUserDefaults] setBool:contentBlockingEnabled forKey:kContentBlockingDefaultsKey];
    [self syncRuleListAttachment];
}

- (NSString *)contentBlockingStatus {
    if (!self.contentBlockingAvailable) {
        return @"Unavailable";
    }
    if (self.ruleListsPreparing) {
        return @"Preparing";
    }
    return @"Ready";
}

@end

#pragma mark - BrowserWebView

@implementation BrowserWebView

+ (BOOL)isWebKitAvailable {
    return BrowserLoadWebKit();
}

- (instancetype)initWithUserAgent:(NSString *)userAgent {
    if ((self = [super initWithFrame:CGRectZero])) {
        _pageZoom = 1.0;
        _blocksPopups = YES;
        _candidatesByURL = [NSMutableDictionary new];
        _orderedCandidates = [NSMutableArray new];
        _pendingPointCompletions = [NSMutableDictionary new];
        _userAgent = [userAgent copy];
        self.backgroundColor = UIColor.blackColor;
        [self installWebKitView];
    }
    return self;
}

/// The settings every tab's WKWebView is created with.
- (id)makeWebViewConfiguration {
    id configuration = [NSClassFromString(@"WKWebViewConfiguration") new];
    BrowserSetBool(configuration, @"setAllowsInlineMediaPlayback:", YES);
    BrowserSetBool(configuration, @"setAllowsAirPlayForMediaPlayback:", NO);
    BrowserSetBool(configuration, @"setAllowsPictureInPictureMediaPlayback:", NO);
    // The page agent synthesises clicks, which WebKit doesn't count as a user gesture; with
    // the default setting no video would start.
    SEL requiringUserAction = NSSelectorFromString(@"setMediaTypesRequiringUserActionForPlayback:");
    if ([configuration respondsToSelector:requiringUserAction]) {
        ((void (*)(id, SEL, NSUInteger))objc_msgSend)(configuration, requiringUserAction, 0);
    }
    BrowserSetObject(configuration, @"setUserContentController:", [BrowserWebEnvironment sharedEnvironment].userContentController);
    BrowserSetObject(configuration, @"setWebsiteDataStore:", [BrowserWebView websiteDataStore]);

    id preferences = BrowserObject(configuration, @"preferences");
    for (NSString *setter in @[@"_setMediaSourceEnabled:", @"_setManagedMediaSourceEnabled:", @"_setMediaCapabilityGrantsEnabled:"]) {
        BrowserSetBool(preferences, setter, YES);
    }
    BrowserSetBool(preferences, @"setJavaScriptCanOpenWindowsAutomatically:", NO);
    return configuration;
}

- (void)installWebKitView {
    Class webViewClass = BrowserLoadWebKit() ? NSClassFromString(@"WKWebView") : Nil;
    id configuration = webViewClass ? [self makeWebViewConfiguration] : nil;
    if (configuration == nil) {
        return;
    }
    UIView<BrowserWKWebView> *webView = ((id (*)(id, SEL, CGRect, id))objc_msgSend)([webViewClass alloc], NSSelectorFromString(@"initWithFrame:configuration:"), self.bounds, configuration);
    if (webView == nil) {
        return;
    }
    // The pointer drives the page through the agent script; WebKit itself never gets touches or focus.
    webView.userInteractionEnabled = NO;
    webView.backgroundColor = UIColor.blackColor;
    webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    webView.navigationDelegate = self;
    webView.UIDelegate = self;
    webView.allowsBackForwardNavigationGestures = NO;
    webView.customUserAgent = self.userAgent;
#if DEBUG
    BrowserSetBool(webView, @"setInspectable:", YES);
#endif
    self.runtimeWebView = webView;
    [[BrowserWebEnvironment sharedEnvironment] registerWebView:self forRuntimeView:webView];

    for (NSString *keyPath in [self observedKeyPaths]) {
        [webView addObserver:self forKeyPath:keyPath options:NSKeyValueObservingOptionNew context:(__bridge void *)[BrowserWebView class]];
    }
    self.observingRuntimeWebView = YES;
    [self addSubview:webView];
}

- (NSArray<NSString *> *)observedKeyPaths {
    return @[@"estimatedProgress", @"title", @"URL", @"canGoBack", @"canGoForward", @"loading"];
}

- (void)dealloc {
    if (self.observingRuntimeWebView) {
        for (NSString *keyPath in [self observedKeyPaths]) {
            @try {
                [self.runtimeWebView removeObserver:self forKeyPath:keyPath context:(__bridge void *)[BrowserWebView class]];
            } @catch (__unused NSException *exception) {}
        }
    }
    self.runtimeWebView.navigationDelegate = nil;
    self.runtimeWebView.UIDelegate = nil;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey, id> *)change context:(void *)context {
    if (context != (__bridge void *)[BrowserWebView class]) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    [self scheduleStateUpdate];
}

- (void)scheduleStateUpdate {
    if (self.stateUpdateScheduled) {
        return;
    }
    self.stateUpdateScheduled = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.stateUpdateScheduled = NO;
        if ([self.delegate respondsToSelector:@selector(webViewDidUpdateState:)]) {
            [self.delegate webViewDidUpdateState:self];
        }
    });
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.runtimeWebView.frame = self.bounds;
}

- (void)setUserInteractionEnabled:(BOOL)userInteractionEnabled {
    // Always off; see -installWebKitView.
    [super setUserInteractionEnabled:NO];
}

#pragma mark State

- (UIScrollView *)scrollView {
    return self.runtimeWebView.scrollView;
}

- (NSURLRequest *)request {
    NSURL *URL = self.runtimeWebView.URL;
    return URL ? [NSURLRequest requestWithURL:URL] : self.lastRequest;
}

- (NSString *)title {
    return self.runtimeWebView.title ?: self.lastTitle;
}

- (BOOL)canGoBack {
    return self.runtimeWebView.canGoBack;
}

- (BOOL)canGoForward {
    return self.runtimeWebView.canGoForward;
}

- (double)estimatedProgress {
    if (self.runtimeWebView == nil) {
        return self.loading ? 0.5 : 1.0;
    }
    return self.runtimeWebView.estimatedProgress;
}

- (NSArray<BrowserMediaCandidate *> *)mediaCandidates {
    return [self.orderedCandidates copy];
}

#pragma mark Navigation

- (void)loadRequest:(NSURLRequest *)request {
    if (request) {
        self.lastRequest = request;
        [self.runtimeWebView loadRequest:request];
    }
}

- (void)reload {
    [self.runtimeWebView reload];
}

- (void)stopLoading {
    [self.runtimeWebView stopLoading];
}

- (void)goBack {
    [self.runtimeWebView goBack];
}

- (void)goForward {
    [self.runtimeWebView goForward];
}

- (void)setUserAgent:(NSString *)userAgent {
    _userAgent = [userAgent copy];
    self.runtimeWebView.customUserAgent = _userAgent;
}

- (void)setPageZoom:(CGFloat)pageZoom {
    _pageZoom = MIN(3.0, MAX(0.3, pageZoom));
    [self applyPageZoom];
}

- (void)applyPageZoom {
    if (self.runtimeWebView == nil) {
        return;
    }
    SEL pageZoomSelector = NSSelectorFromString(@"setPageZoom:");
    if ([self.runtimeWebView respondsToSelector:pageZoomSelector]) {
        ((void (*)(id, SEL, CGFloat))objc_msgSend)(self.runtimeWebView, pageZoomSelector, self.pageZoom);
        return;
    }
    NSString *script = fabs(self.pageZoom - 1.0) < 0.001
        ? @"document.documentElement.style.zoom='';"
        : [NSString stringWithFormat:@"document.documentElement.style.zoom='%0.3f';", self.pageZoom];
    [self evaluateJavaScript:script completion:nil];
}

#pragma mark JavaScript

- (void)evaluateJavaScript:(NSString *)script completion:(void (^)(id))completion {
    void (^reply)(id) = completion ?: ^(id result) {};
    if (script.length == 0 || self.runtimeWebView == nil) {
        reply(nil);
        return;
    }
    [self.runtimeWebView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
#if DEBUG
        if (error) {
            NSLog(@"[Debug] Script failed: %@", error.localizedDescription);
        }
#endif
        reply(error ? nil : result);
    }];
}

- (void)performPointCommand:(NSString *)command
                    atPoint:(CGPoint)point
                       data:(NSDictionary *)data
                 completion:(void (^)(NSDictionary *))completion {
    CGFloat viewWidth = CGRectGetWidth(self.bounds);
    if (self.runtimeWebView == nil || viewWidth <= 0.0) {
        if (completion != nil) {
            completion(nil);
        }
        return;
    }

    self.nextPointCommandIdentifier += 1;
    NSNumber *identifier = @(self.nextPointCommandIdentifier);
    if (completion != nil) {
        self.pendingPointCompletions[identifier] = [completion copy];
        // A frame without the agent (or a navigation in flight) never answers.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self finishPointCommand:identifier result:nil];
        });
    }

    NSString *token = [BrowserWebEnvironment sharedEnvironment].agentToken;
    NSString *script = [NSString stringWithFormat:
                        @"(window.__tvbAgent ? window.__tvbAgent.point('%@', %@, %0.2f, %0.2f, %0.2f, %@, %@) : 'missing')",
                        token, BrowserJSONLiteral(command), point.x, point.y, viewWidth, identifier, BrowserJSONLiteral(data)];
    __weak typeof(self) weakSelf = self;
    [self evaluateJavaScript:script completion:^(id result) {
        NSString *status = BrowserJavaScriptString(result);
        if (status == nil || [status isEqualToString:@"missing"] || [status isEqualToString:@"denied"] || [status isEqualToString:@"error"]) {
            [weakSelf finishPointCommand:identifier result:nil];
        }
    }];
}

- (void)finishPointCommand:(NSNumber *)identifier result:(NSDictionary *)result {
    void (^completion)(NSDictionary *) = self.pendingPointCompletions[identifier];
    if (completion == nil) {
        return;
    }
    [self.pendingPointCompletions removeObjectForKey:identifier];
    completion(result);
}

- (void)takeSnapshotWithCompletion:(void (^)(UIImage *))completion {
    SEL snapshotSelector = NSSelectorFromString(@"takeSnapshotWithConfiguration:completionHandler:");
    if (self.runtimeWebView == nil || CGRectIsEmpty(self.bounds) || ![self.runtimeWebView respondsToSelector:snapshotSelector]) {
        completion(nil);
        return;
    }
    id configuration = nil;
    Class configurationClass = NSClassFromString(@"WKSnapshotConfiguration");
    if (configurationClass != Nil) {
        configuration = [configurationClass new];
        BrowserSetObject(configuration, @"setSnapshotWidth:", @(640));
        BrowserSetBool(configuration, @"setAfterScreenUpdates:", NO);
    }
    __weak typeof(self) weakSelf = self;
    ((void (*)(id, SEL, id, id))objc_msgSend)(self.runtimeWebView, snapshotSelector, configuration, ^(UIImage *image, NSError *error) {
        if (image != nil && error == nil) {
            completion(image);
            return;
        }
        // WebKit's snapshot API is not reliable on tvOS; drawing the view works while it is on screen.
        completion([weakSelf renderedSnapshot]);
    });
}

- (UIImage *)renderedSnapshot {
    if (self.window == nil || CGRectIsEmpty(self.bounds)) {
        return nil;
    }
    CGFloat scale = MIN(1.0, 640.0 / CGRectGetWidth(self.bounds));
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = scale;
    format.opaque = YES;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:self.bounds.size format:format];
    return [renderer imageWithActions:^(__unused UIGraphicsImageRendererContext *context) {
        [self drawViewHierarchyInRect:self.bounds afterScreenUpdates:NO];
    }];
}

- (NSData *)interactionState {
    id state = BrowserObject(self.runtimeWebView, @"interactionState");
    return [state isKindOfClass:[NSData class]] ? state : nil;
}

- (void)setInteractionState:(NSData *)interactionState {
    if (interactionState.length == 0) {
        return;
    }
    @try {
        BrowserSetObject(self.runtimeWebView, @"setInteractionState:", interactionState);
    } @catch (__unused NSException *exception) {
        // A state saved by a different WebKit version is ignored; the tab then loads its URL.
    }
}

- (void)fetchPageColorWithCompletion:(void (^)(UIColor *))completion {
    NSString *token = [BrowserWebEnvironment sharedEnvironment].agentToken;
    NSString *script = [NSString stringWithFormat:@"(window.__tvbAgent ? window.__tvbAgent.pageInfo('%@') : '')", token];
    [self evaluateJavaScript:script completion:^(id result) {
        UIColor *color = nil;
        NSData *data = [BrowserString(result) dataUsingEncoding:NSUTF8StringEncoding];
        if (data.length > 0) {
            NSDictionary *info = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([info isKindOfClass:[NSDictionary class]]) {
                color = BrowserColorFromCSSString(BrowserString(info[@"color"]));
            }
        }
        completion(color);
    }];
}

- (void)pauseAllMediaPlayback {
    if (self.runtimeWebView == nil) {
        return;
    }
    SEL pauseSelector = NSSelectorFromString(@"pauseAllMediaPlaybackWithCompletionHandler:");
    if ([self.runtimeWebView respondsToSelector:pauseSelector]) {
        ((void (*)(id, SEL, id))objc_msgSend)(self.runtimeWebView, pauseSelector, nil);
    }
    NSString *token = [BrowserWebEnvironment sharedEnvironment].agentToken;
    [self evaluateJavaScript:[NSString stringWithFormat:@"window.__tvbAgent && window.__tvbAgent.pauseAll('%@')", token] completion:nil];
}

#pragma mark Agent messages

- (void)handleAgentMessage:(NSDictionary *)message fromMainFrame:(BOOL)fromMainFrame {
    NSString *type = BrowserString(message[@"t"]);
    NSString *frameURLString = BrowserString(message[@"frameURL"]);

    if ([type isEqualToString:@"point"]) {
        NSNumber *identifier = [message[@"id"] isKindOfClass:[NSNumber class]] ? message[@"id"] : nil;
        NSDictionary *result = [message[@"result"] isKindOfClass:[NSDictionary class]] ? message[@"result"] : @{};
        if (identifier != nil) {
            NSMutableDictionary *annotated = [result mutableCopy];
            annotated[@"mainFrame"] = @(fromMainFrame);
            annotated[@"frameURL"] = frameURLString;
            [self finishPointCommand:identifier result:annotated];
        }
        return;
    }

    if ([type isEqualToString:@"log"]) {
#if DEBUG
        NSLog(@"[Agent] %@ (%@)", BrowserString(message[@"msg"]), frameURLString);
#endif
        return;
    }

    if ([type isEqualToString:@"media"]) {
        NSDictionary *media = [message[@"media"] isKindOfClass:[NSDictionary class]] ? message[@"media"] : nil;
        [self noteMediaDictionary:media frameURLString:frameURLString fromMainFrame:fromMainFrame pageTitle:BrowserString(message[@"title"]) notify:YES];
        return;
    }

    if ([type isEqualToString:@"fullscreen"]) {
        NSMutableDictionary *info = [NSMutableDictionary dictionary];
        if ([message[@"video"] isKindOfClass:[NSDictionary class]]) {
            info[@"video"] = message[@"video"];
        }
        info[@"src"] = BrowserString(message[@"src"]);
        info[@"blob"] = @([message[@"blob"] respondsToSelector:@selector(boolValue)] && [message[@"blob"] boolValue]);
        info[@"frameURL"] = frameURLString;
        info[@"mainFrame"] = @(fromMainFrame);
        if ([message[@"hls"] isKindOfClass:[NSDictionary class]]) {
            info[@"hls"] = message[@"hls"];
        }
        if ([message[@"subtitles"] isKindOfClass:[NSArray class]]) {
            info[@"subtitles"] = message[@"subtitles"];
        }
        if ([self.delegate respondsToSelector:@selector(webView:didRequestFullscreenVideo:)]) {
            [self.delegate webView:self didRequestFullscreenVideo:info];
        }
        return;
    }

    if ([type isEqualToString:@"playing"]) {
        NSMutableDictionary *info = [NSMutableDictionary dictionary];
        if ([message[@"video"] isKindOfClass:[NSDictionary class]]) {
            [info addEntriesFromDictionary:message[@"video"]];
        }
        info[@"src"] = BrowserString(message[@"src"]);
        info[@"blob"] = @([message[@"blob"] respondsToSelector:@selector(boolValue)] && [message[@"blob"] boolValue]);
        info[@"frameURL"] = frameURLString;
        info[@"mainFrame"] = @(fromMainFrame);
        if ([self.delegate respondsToSelector:@selector(webView:videoDidStartPlaying:)]) {
            [self.delegate webView:self videoDidStartPlaying:info];
        }
    }
}

- (BrowserMediaCandidate *)noteMediaDictionary:(NSDictionary *)media
                                frameURLString:(NSString *)frameURLString
                                 fromMainFrame:(BOOL)fromMainFrame
                                     pageTitle:(NSString *)pageTitle
                                        notify:(BOOL)notify {
    NSString *URLString = BrowserString(media[@"url"]);
    NSURL *URL = URLString.length > 0 ? [NSURL URLWithString:URLString] : nil;
    if (URL == nil || !([URL.scheme.lowercaseString isEqualToString:@"http"] || [URL.scheme.lowercaseString isEqualToString:@"https"])) {
        return nil;
    }

    BrowserMediaCandidate *candidate = self.candidatesByURL[URLString];
    if (candidate == nil) {
        candidate = [BrowserMediaCandidate new];
        candidate.URL = URL;
        candidate.frameURLString = frameURLString;
        candidate.fromMainFrame = fromMainFrame;
        candidate.firstSeen = [NSDate date];
        self.candidatesByURL[URLString] = candidate;
        [self.orderedCandidates addObject:candidate];
        if (self.orderedCandidates.count > 60) {
            BrowserMediaCandidate *oldest = self.orderedCandidates.firstObject;
            [self.orderedCandidates removeObjectAtIndex:0];
            [self.candidatesByURL removeObjectForKey:oldest.URL.absoluteString];
        }
    }
    candidate.pageTitle = pageTitle.length > 0 ? pageTitle : (candidate.pageTitle ?: @"");
    [candidate updateFromDictionary:media];
    if (notify && [self.delegate respondsToSelector:@selector(webView:didDetectMedia:)]) {
        [self.delegate webView:self didDetectMedia:candidate];
    }
    return candidate;
}

- (void)resetPageState {
    [self.candidatesByURL removeAllObjects];
    [self.orderedCandidates removeAllObjects];
    self.blockedRequestCount = 0;
}

#pragma mark WKNavigationDelegate / WKUIDelegate

- (void)notifyLoadFailure:(NSError *)error {
    self.loading = NO;
    if ([self.delegate respondsToSelector:@selector(webView:didFailLoadWithError:)]) {
        [self.delegate webView:self didFailLoadWithError:error];
    }
}

- (void)webView:(id)webView didStartProvisionalNavigation:(id)navigation {
    self.loading = YES;
    if ([self.delegate respondsToSelector:@selector(webViewDidStartLoad:)]) {
        [self.delegate webViewDidStartLoad:self];
    }
}

- (void)webView:(id)webView didCommitNavigation:(id)navigation {
    [self resetPageState];
    [self applyPageZoom];
    [self scheduleStateUpdate];
}

- (void)webView:(id)webView didFinishNavigation:(id)navigation {
    self.loading = NO;
    self.processTerminationCount = 0;
    // Remember what loaded, in case WebKit later reports nothing (a crashed content process).
    self.lastTitle = self.runtimeWebView.title ?: self.lastTitle;
    if (self.runtimeWebView.URL) {
        self.lastRequest = [NSURLRequest requestWithURL:self.runtimeWebView.URL];
    }
    [self applyPageZoom];
    if ([self.delegate respondsToSelector:@selector(webViewDidFinishLoad:)]) {
        [self.delegate webViewDidFinishLoad:self];
    }
}

- (void)webView:(id)webView didFailNavigation:(id)navigation withError:(NSError *)error {
    [self notifyLoadFailure:error];
}

- (void)webView:(id)webView didFailProvisionalNavigation:(id)navigation withError:(NSError *)error {
    [self notifyLoadFailure:error];
}

- (void)webViewWebContentProcessDidTerminate:(id)webView {
    self.loading = NO;
    // Usually memory pressure. Bring the page back once; do not loop on a page that keeps crashing.
    self.processTerminationCount += 1;
    if (self.processTerminationCount <= 1) {
        [self reload];
    }
}

// Private WKNavigationDelegate callback; lets the menu show how much was blocked.
- (void)_webView:(id)webView contentRuleListWithIdentifier:(NSString *)identifier performedAction:(id)action forURL:(NSURL *)URL {
    if (BrowserBool(action, @"blockedLoad")) {
        self.blockedRequestCount += 1;
    }
}

/// Schemes a web page can actually be shown from. Everything else (App Store links, tel:,
/// intent: and the like, which ad redirects are fond of) has nowhere to go on a TV.
static BOOL BrowserIsWebScheme(NSString *scheme) {
    static NSSet<NSString *> *schemes;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        schemes = [NSSet setWithObjects:@"http", @"https", @"about", @"blob", @"data", @"file", @"javascript", nil];
    });
    return scheme.length == 0 || [schemes containsObject:scheme.lowercaseString];
}

- (void)webView:(id)webView decidePolicyForNavigationAction:(id<BrowserWKNavigationAction>)action decisionHandler:(void (^)(NSInteger policy))decisionHandler {
    // WKNavigationActionPolicy: 0 cancels, 1 allows.
    NSURLRequest *request = action.request;
    if (!BrowserIsWebScheme(request.URL.scheme)) {
        decisionHandler(0);
        return;
    }
    // Subframe navigations (players, ads in iframes) are always the page's own business.
    BOOL topLevel = action.targetFrame == nil || action.targetFrame.isMainFrame;
    BOOL allowed = !topLevel
        || ![self.delegate respondsToSelector:@selector(webView:shouldStartLoadWithRequest:navigationType:)]
        || [self.delegate webView:self shouldStartLoadWithRequest:request navigationType:action.navigationType];
    if (allowed && topLevel && request) {
        self.lastRequest = request;
    }
    decisionHandler(allowed ? 1 : 0);
}

/// window.open and target=_blank. A tab's page never gets a second WKWebView: links open in a
/// new browser tab (or this one), everything else counts as a pop-up.
- (id)webView:(id)webView createWebViewWithConfiguration:(id)configuration forNavigationAction:(id<BrowserWKNavigationAction>)action windowFeatures:(id)windowFeatures {
    NSURLRequest *request = action.request;
    // 0 is a link the user followed; anything else is script calling window.open, which on
    // the sites this browser gets used for is nearly always an advert.
    BOOL followedLink = action.navigationType == 0;
    if (!followedLink && self.blocksPopups) {
        if ([self.delegate respondsToSelector:@selector(webView:didBlockPopupWithRequest:)]) {
            [self.delegate webView:self didBlockPopupWithRequest:request];
        }
        return nil;
    }
    if (request.URL == nil || !BrowserIsWebScheme(request.URL.scheme)) {
        return nil;
    }
    BOOL openedInNewTab = [self.delegate respondsToSelector:@selector(webView:shouldCreateNewTabWithRequest:navigationType:)]
        && [self.delegate webView:self shouldCreateNewTabWithRequest:request navigationType:action.navigationType];
    if (!openedInNewTab) {
        [self loadRequest:request];
    }
    return nil;
}

#pragma mark Website data

/// WebKit keeps local storage, IndexedDB and the like under Library/WebKit, which tvOS apps
/// may not write to: sites lost everything they saved (a player's chosen voice-over, its
/// resume point, a theme switch, some logins) at every launch. This store keeps it in Caches.
+ (id)cachesWebsiteDataStore {
    static id store = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class configurationClass = NSClassFromString(@"_WKWebsiteDataStoreConfiguration");
        Class dataStoreClass = NSClassFromString(@"WKWebsiteDataStore");
        SEL initializer = NSSelectorFromString(@"_initWithConfiguration:");
        if (configurationClass == Nil || dataStoreClass == Nil || ![dataStoreClass instancesRespondToSelector:initializer]) {
            return;
        }
        NSURL *caches = [[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
        NSURL *root = [caches URLByAppendingPathComponent:@"WebsiteData" isDirectory:YES];
        NSURL *webKitCaches = [caches URLByAppendingPathComponent:@"WebKit" isDirectory:YES];
        id configuration = [configurationClass new];
        NSDictionary<NSString *, NSURL *> *directories = @{
            @"_setWebStorageDirectory:": [root URLByAppendingPathComponent:@"LocalStorage" isDirectory:YES],
            @"_setIndexedDBDatabaseDirectory:": [root URLByAppendingPathComponent:@"IndexedDB" isDirectory:YES],
            @"_setWebSQLDatabaseDirectory:": [root URLByAppendingPathComponent:@"WebSQL" isDirectory:YES],
            @"_setResourceLoadStatisticsDirectory:": [root URLByAppendingPathComponent:@"ResourceLoadStatistics" isDirectory:YES],
            @"_setCacheStorageDirectory:": [root URLByAppendingPathComponent:@"CacheStorage" isDirectory:YES],
            @"_setServiceWorkerRegistrationDirectory:": [root URLByAppendingPathComponent:@"ServiceWorkers" isDirectory:YES],
            @"setGeneralStorageDirectory:": [root URLByAppendingPathComponent:@"Default" isDirectory:YES],
            @"setMediaKeysStorageDirectory:": [root URLByAppendingPathComponent:@"MediaKeys" isDirectory:YES],
            @"setDeviceIdHashSaltsStorageDirectory:": [root URLByAppendingPathComponent:@"DeviceIdHashSalts" isDirectory:YES],
            @"setSearchFieldHistoryDirectory:": [root URLByAppendingPathComponent:@"SearchHistory" isDirectory:YES],
            @"setResourceMonitorThrottlerDirectory:": [root URLByAppendingPathComponent:@"ResourceMonitorThrottler" isDirectory:YES],
            @"setNetworkCacheDirectory:": [webKitCaches URLByAppendingPathComponent:@"NetworkCache" isDirectory:YES],
            @"setHSTSStorageDirectory:": [webKitCaches URLByAppendingPathComponent:@"HSTS" isDirectory:YES],
            @"setAlternativeServicesStorageDirectory:": [webKitCaches URLByAppendingPathComponent:@"AlternativeServices" isDirectory:YES],
        };
        NSUInteger applied = 0;
        for (NSString *selectorName in directories) {
            if ([configuration respondsToSelector:NSSelectorFromString(selectorName)]) {
                [[NSFileManager defaultManager] createDirectoryAtURL:directories[selectorName] withIntermediateDirectories:YES attributes:nil error:nil];
                BrowserSetObject(configuration, selectorName, directories[selectorName]);
                applied += 1;
            }
        }
        // Without somewhere for local storage the store is no better than the default one.
        if (![configuration respondsToSelector:NSSelectorFromString(@"_setWebStorageDirectory:")] &&
            ![configuration respondsToSelector:NSSelectorFromString(@"setGeneralStorageDirectory:")]) {
            return;
        }
        store = ((id (*)(id, SEL, id))objc_msgSend)([dataStoreClass alloc], initializer, configuration);
        NSLog(@"[Browser] Website data in Caches (%lu locations): %@", (unsigned long)applied, store != nil ? @"ready" : @"failed");
    });
    return store;
}

/// The store every tab shares: the Caches-based one where WebKit supports it, otherwise WebKit's default.
+ (id<BrowserWKWebsiteDataStore>)websiteDataStore {
    if (!BrowserLoadWebKit()) {
        return nil;
    }
    return [self cachesWebsiteDataStore] ?: [(Class<BrowserWKWebsiteDataStore>)NSClassFromString(@"WKWebsiteDataStore") defaultDataStore];
}

+ (NSArray<NSHTTPCookie *> *)allCookies {
    id<BrowserWKHTTPCookieStore> cookieStore = [self websiteDataStore].httpCookieStore;
    if (cookieStore == nil) {
        return NSHTTPCookieStorage.sharedHTTPCookieStorage.cookies ?: @[];
    }
    __block NSArray<NSHTTPCookie *> *cookies = @[];
    BrowserWaitForWork(3.0, ^(dispatch_block_t finish) {
        [cookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *found) {
            cookies = found ?: @[];
            finish();
        }];
    });
    return cookies;
}

+ (NSData *)cookieDataRepresentation {
    return [NSKeyedArchiver archivedDataWithRootObject:[self allCookies] requiringSecureCoding:NO error:NULL];
}

+ (void)restoreCookiesFromData:(NSData *)cookieData {
    NSSet<Class> *classes = [NSSet setWithObjects:[NSArray class], [NSHTTPCookie class], nil];
    NSArray<NSHTTPCookie *> *cookies = cookieData.length > 0 ? [NSKeyedUnarchiver unarchivedObjectOfClasses:classes fromData:cookieData error:NULL] : nil;
    if (![cookies isKindOfClass:[NSArray class]] || cookies.count == 0) {
        return;
    }
    id<BrowserWKHTTPCookieStore> cookieStore = [self websiteDataStore].httpCookieStore;
    if (cookieStore == nil) {
        for (NSHTTPCookie *cookie in cookies) {
            [NSHTTPCookieStorage.sharedHTTPCookieStorage setCookie:cookie];
        }
        return;
    }
    // Wait, so the first page load already has its cookies.
    BrowserWaitForWork(3.0, ^(dispatch_block_t finish) {
        dispatch_group_t group = dispatch_group_create();
        for (NSHTTPCookie *cookie in cookies) {
            dispatch_group_enter(group);
            [cookieStore setCookie:cookie completionHandler:^{ dispatch_group_leave(group); }];
        }
        dispatch_group_notify(group, dispatch_get_main_queue(), finish);
    });
}

/// Calls `completion` on the main queue once WebKit has removed `dataTypes` (all of them when nil).
+ (void)removeWebsiteDataOfTypes:(NSSet<NSString *> *)dataTypes completion:(void (^)(void))completion {
    void (^done)(void) = ^{
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), completion);
        }
    };
    [[NSURLCache sharedURLCache] removeAllCachedResponses];
    id<BrowserWKWebsiteDataStore> store = [self websiteDataStore];
    if (store == nil) {
        done();
        return;
    }
    NSSet<NSString *> *types = dataTypes ?: [(Class<BrowserWKWebsiteDataStore>)NSClassFromString(@"WKWebsiteDataStore") allWebsiteDataTypes];
    [store removeDataOfTypes:types modifiedSince:[NSDate distantPast] completionHandler:done];
}

+ (void)clearCachedDataWithCompletion:(void (^)(void))completion {
    NSSet<NSString *> *everything = [(Class<BrowserWKWebsiteDataStore>)NSClassFromString(@"WKWebsiteDataStore") allWebsiteDataTypes];
    NSPredicate *notCookies = [NSPredicate predicateWithFormat:@"NOT (SELF CONTAINS[c] 'cookie')"];
    [self removeWebsiteDataOfTypes:[everything filteredSetUsingPredicate:notCookies] ?: [NSSet set] completion:completion];
}

+ (void)clearCookiesWithCompletion:(void (^)(void))completion {
    id<BrowserWKHTTPCookieStore> cookieStore = [self websiteDataStore].httpCookieStore;
    if (cookieStore == nil) {
        NSHTTPCookieStorage *storage = NSHTTPCookieStorage.sharedHTTPCookieStorage;
        [storage.cookies enumerateObjectsUsingBlock:^(NSHTTPCookie *cookie, NSUInteger index, BOOL *stop) {
            [storage deleteCookie:cookie];
        }];
        if (completion) {
            completion();
        }
        return;
    }
    [cookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
        dispatch_group_t group = dispatch_group_create();
        for (NSHTTPCookie *cookie in cookies) {
            dispatch_group_enter(group);
            [cookieStore deleteCookie:cookie completionHandler:^{ dispatch_group_leave(group); }];
        }
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            if (completion) {
                completion();
            }
        });
    }];
}

+ (void)resetWebsiteDataWithCompletion:(void (^)(void))completion {
    [self removeWebsiteDataOfTypes:nil completion:completion];
}

@end
