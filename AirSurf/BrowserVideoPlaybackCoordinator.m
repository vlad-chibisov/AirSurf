#import "BrowserVideoPlaybackCoordinator.h"

#import "BrowserLibraryStore.h"
#import "BrowserPlayerViewController.h"
#import "BrowserWebView.h"

/// Playlists requested within this gap of each other belong to one stream (master + variants).
static NSTimeInterval const kPlaylistClusterGap = 5.0;

@interface BrowserVideoPlaybackCoordinator ()

@property (nonatomic, weak) id<BrowserVideoPlaybackCoordinatorHost> host;
@property (nonatomic) NSMutableSet<NSString *> *failedURLStrings;
@property (nonatomic) BOOL playerPresented;
/// Quality / voice-over / subtitles picked in the page's player, for the player about to open.
@property (nonatomic, copy, nullable) NSDictionary *pendingMediaPreferences;
/// Subtitle files the page's player had for that video, and the video's length.
@property (nonatomic, copy, nullable) NSArray<NSDictionary *> *pendingSubtitles;
@property (nonatomic) NSTimeInterval pendingDuration;

@end

@implementation BrowserVideoPlaybackCoordinator

- (instancetype)initWithHost:(id<BrowserVideoPlaybackCoordinatorHost>)host {
    self = [super init];
    if (self) {
        _host = host;
        _failedURLStrings = [NSMutableSet set];
    }
    return self;
}

+ (BOOL)URLLooksLikeMedia:(NSURL *)URL {
    NSString *scheme = URL.scheme.lowercaseString;
    if (!([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])) {
        return NO;
    }
    return [@[@"m3u8", @"mp4", @"m4v", @"mov"] containsObject:URL.pathExtension.lowercaseString];
}

- (void)webViewDidNavigate:(BrowserWebView *)webView {
    [self.failedURLStrings removeAllObjects];
}

#pragma mark Choosing a stream

- (BOOL)candidateIsUsable:(BrowserMediaCandidate *)candidate {
    if (!candidate.isPlayableNatively || [self.failedURLStrings containsObject:candidate.URL.absoluteString]) {
        return NO;
    }
    if (candidate.fromElement) {
        // Decorative background loops and tiny preview players are not what anyone means by "the video".
        if (candidate.muted && candidate.loops) {
            return NO;
        }
        if (candidate.elementSize.width > 0.0 && candidate.elementSize.width < 200.0) {
            return NO;
        }
    }
    return YES;
}

- (BrowserMediaCandidate *)bestCandidateAmong:(NSArray<BrowserMediaCandidate *> *)candidates {
    NSMutableArray<BrowserMediaCandidate *> *playlists = [NSMutableArray array];
    NSMutableArray<BrowserMediaCandidate *> *files = [NSMutableArray array];
    for (BrowserMediaCandidate *candidate in candidates) {
        if (![self candidateIsUsable:candidate]) {
            continue;
        }
        if (candidate.kind == BrowserMediaKindHLS) {
            [playlists addObject:candidate];
        } else {
            [files addObject:candidate];
        }
    }

    if (playlists.count > 0) {
        // A player fetches the master playlist first and its quality variants right after.
        // Take the newest burst of requests, and from that burst the master (or the first).
        NSUInteger clusterStart = playlists.count - 1;
        while (clusterStart > 0 &&
               [playlists[clusterStart].firstSeen timeIntervalSinceDate:playlists[clusterStart - 1].firstSeen] < kPlaylistClusterGap) {
            clusterStart -= 1;
        }
        NSArray<BrowserMediaCandidate *> *cluster = [playlists subarrayWithRange:NSMakeRange(clusterStart, playlists.count - clusterStart)];
        for (BrowserMediaCandidate *candidate in cluster) {
            if (candidate.isMasterPlaylist) {
                return candidate;
            }
        }
        for (BrowserMediaCandidate *candidate in cluster) {
            if (candidate.fromElement) {
                return candidate;
            }
        }
        return cluster.firstObject;
    }

    BrowserMediaCandidate *bestFile = nil;
    for (BrowserMediaCandidate *candidate in files) {
        if (!candidate.fromElement) {
            continue;
        }
        if (bestFile == nil || candidate.duration >= bestFile.duration) {
            bestFile = candidate;
        }
    }
    return bestFile ?: files.lastObject;
}

- (BrowserMediaCandidate *)bestCandidateInWebView:(BrowserWebView *)webView frameURLString:(NSString *)frameURLString {
    NSArray<BrowserMediaCandidate *> *all = webView.mediaCandidates;
    if (frameURLString.length > 0) {
        NSMutableArray<BrowserMediaCandidate *> *sameFrame = [NSMutableArray array];
        for (BrowserMediaCandidate *candidate in all) {
            if ([candidate.frameURLString isEqualToString:frameURLString]) {
                [sameFrame addObject:candidate];
            }
        }
        BrowserMediaCandidate *best = [self bestCandidateAmong:sameFrame];
        if (best != nil) {
            return best;
        }
    }
    return [self bestCandidateAmong:all];
}

- (NSArray<BrowserMediaCandidate *> *)playableCandidatesInWebView:(BrowserWebView *)webView {
    if (webView == nil) {
        return @[];
    }
    NSMutableArray<BrowserMediaCandidate *> *usable = [NSMutableArray array];
    for (BrowserMediaCandidate *candidate in webView.mediaCandidates) {
        if ([self candidateIsUsable:candidate]) {
            [usable addObject:candidate];
        }
    }
    BrowserMediaCandidate *best = [self bestCandidateAmong:usable];
    if (best != nil) {
        [usable removeObject:best];
        // Newest first after the best guess.
        NSArray<BrowserMediaCandidate *> *rest = [[usable reverseObjectEnumerator] allObjects];
        return [@[best] arrayByAddingObjectsFromArray:rest];
    }
    return usable;
}

#pragma mark Page events

- (void)noteClickResult:(NSDictionary *)result inWebView:(BrowserWebView *)webView {
    if (!self.host.browserNativeVideoPlayerEnabled || webView == nil || self.playerPresented) {
        return;
    }
    BOOL fullscreenControl = [result[@"fullscreenControl"] respondsToSelector:@selector(boolValue)] && [result[@"fullscreenControl"] boolValue];
    NSDictionary *video = [result[@"video"] isKindOfClass:[NSDictionary class]] ? result[@"video"] : nil;
    if (!fullscreenControl || ![result[@"action"] isEqual:@"click"]) {
        return;
    }
    // Most players answer the click by asking for fullscreen, which arrives separately and
    // carries the exact stream. Players that fake fullscreen with CSS never ask, so the
    // click itself is the request.
    NSString *frameURLString = [result[@"frameURL"] isKindOfClass:[NSString class]] ? result[@"frameURL"] : @"";
    NSMutableDictionary *request = [NSMutableDictionary dictionary];
    request[@"frameURL"] = frameURLString;
    if (video != nil) {
        request[@"video"] = video;
        request[@"src"] = [video[@"src"] isKindOfClass:[NSString class]] ? video[@"src"] : @"";
        if ([video[@"hls"] isKindOfClass:[NSDictionary class]]) {
            request[@"hls"] = video[@"hls"];
        }
        if ([video[@"subtitles"] isKindOfClass:[NSArray class]]) {
            request[@"subtitles"] = video[@"subtitles"];
        }
    }
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!weakSelf.playerPresented) {
            [weakSelf webView:webView didRequestFullscreenVideo:request];
        }
    });
}

- (BrowserMediaCandidate *)candidateWithURLString:(NSString *)URLString inWebView:(BrowserWebView *)webView {
    for (BrowserMediaCandidate *candidate in webView.mediaCandidates) {
        if ([candidate.URL.absoluteString isEqualToString:URLString]) {
            return candidate;
        }
    }
    return nil;
}

- (void)webView:(BrowserWebView *)webView didRequestFullscreenVideo:(NSDictionary *)info {
    if (!self.host.browserNativeVideoPlayerEnabled || self.playerPresented || webView == nil) {
        return;
    }
    NSString *frameURLString = [info[@"frameURL"] isKindOfClass:[NSString class]] ? info[@"frameURL"] : @"";
    NSString *source = [info[@"src"] isKindOfClass:[NSString class]] ? info[@"src"] : @"";
    NSDictionary *video = [info[@"video"] isKindOfClass:[NSDictionary class]] ? info[@"video"] : @{};
    NSTimeInterval position = [video[@"position"] respondsToSelector:@selector(doubleValue)] ? [video[@"position"] doubleValue] : 0.0;
#if DEBUG
    NSLog(@"[Video] fullscreen requested in %@ src=%@ position=%.1f hls=%@ subtitles=%@", frameURLString, source, position, info[@"hls"], info[@"subtitles"]);
#endif

    self.pendingMediaPreferences = [info[@"hls"] isKindOfClass:[NSDictionary class]] ? info[@"hls"] : nil;
    self.pendingSubtitles = [info[@"subtitles"] isKindOfClass:[NSArray class]] ? info[@"subtitles"] : nil;
    self.pendingDuration = [video[@"duration"] respondsToSelector:@selector(doubleValue)] ? [video[@"duration"] doubleValue] : 0.0;
    NSURL *sourceURL = source.length > 0 ? [NSURL URLWithString:source] : nil;
    BrowserMediaCandidate *candidate = sourceURL != nil ? [self candidateWithURLString:source inWebView:webView] : nil;
    if (candidate != nil && candidate.isPlayableNatively) {
        // Exactly what the page's player is playing: same voice-over, same quality choice.
        [self playCandidate:candidate fromWebView:webView startPosition:position];
        return;
    }
    if (sourceURL != nil && candidate == nil && ![sourceURL.pathExtension.lowercaseString isEqualToString:@"webm"]) {
        NSString *title = [[self class] cleanTitle:webView.title];
        [self presentPlayerForURL:sourceURL title:title referrerString:frameURLString
                        resumeKey:[self resumeKeyForWebView:webView] startPosition:position webView:webView];
        return;
    }
    // The page plays through Media Source (a blob: URL), so use the stream it fetched most recently.
    BrowserMediaCandidate *best = [self bestCandidateInWebView:webView frameURLString:frameURLString];
    if (best != nil) {
        [self playCandidate:best fromWebView:webView startPosition:position];
        return;
    }
    self.pendingMediaPreferences = nil;
    self.pendingSubtitles = nil;
    [self.host browserShowStatus:@"Start the video in the page first, then choose full screen" symbolName:@"play.rectangle"];
}

#pragma mark Playback

- (NSString *)originForURLString:(NSString *)URLString {
    NSURL *URL = [NSURL URLWithString:URLString ?: @""];
    if (URL.host.length == 0) {
        return nil;
    }
    NSString *origin = [NSString stringWithFormat:@"%@://%@", URL.scheme ?: @"https", URL.host];
    if (URL.port != nil) {
        origin = [origin stringByAppendingFormat:@":%@", URL.port];
    }
    return origin;
}

- (NSArray<NSHTTPCookie *> *)cookiesForURL:(NSURL *)URL {
    NSString *host = URL.host.lowercaseString;
    if (host.length == 0) {
        return @[];
    }
    NSMutableArray<NSHTTPCookie *> *matching = [NSMutableArray array];
    for (NSHTTPCookie *cookie in [BrowserWebView allCookies]) {
        NSString *domain = cookie.domain.lowercaseString ?: @"";
        if ([domain hasPrefix:@"."]) {
            domain = [domain substringFromIndex:1];
        }
        if (domain.length > 0 && ([host isEqualToString:domain] || [host hasSuffix:[@"." stringByAppendingString:domain]])) {
            [matching addObject:cookie];
        }
    }
    return matching;
}

- (NSString *)resumeKeyForWebView:(BrowserWebView *)webView {
    NSURLComponents *components = [NSURLComponents componentsWithURL:webView.request.URL resolvingAgainstBaseURL:NO];
    components.fragment = nil;
    return components.string ?: @"";
}

- (void)playCandidate:(BrowserMediaCandidate *)candidate fromWebView:(BrowserWebView *)webView {
    [self playCandidate:candidate fromWebView:webView startPosition:0.0];
}

/// Page titles on film sites are mostly search-engine bait: "Name (2024) watch online free in HD".
+ (NSString *)cleanTitle:(NSString *)title {
    NSString *cleaned = [title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    NSArray<NSString *> *cutMarkers = @[@" смотреть", @" Смотреть", @" онлайн", @" watch online", @" Watch online", @" — ", @" | ", @" - "];
    for (NSString *marker in cutMarkers) {
        NSRange range = [cleaned rangeOfString:marker];
        if (range.location != NSNotFound && range.location >= 8) {
            cleaned = [cleaned substringToIndex:range.location];
        }
    }
    return [cleaned stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

+ (NSString *)siteNameForURL:(NSURL *)URL {
    NSString *host = URL.host ?: @"";
    return [host hasPrefix:@"www."] ? [host substringFromIndex:4] : host;
}

- (void)playCandidate:(BrowserMediaCandidate *)candidate fromWebView:(BrowserWebView *)webView startPosition:(NSTimeInterval)startPosition {
    if (candidate == nil || self.playerPresented) {
        return;
    }
    NSString *title = [[self class] cleanTitle:webView.title.length > 0 ? webView.title : candidate.pageTitle];
    [self presentPlayerForURL:candidate.URL
                        title:title
               referrerString:candidate.frameURLString
                    resumeKey:[self resumeKeyForWebView:webView]
                startPosition:startPosition
                      webView:webView];
}

- (BOOL)playMediaURLIfPossible:(NSURL *)URL referrer:(NSString *)referrer title:(NSString *)title {
    if (!self.host.browserNativeVideoPlayerEnabled || self.playerPresented || ![[self class] URLLooksLikeMedia:URL]) {
        return NO;
    }
    NSString *displayTitle = title.length > 0 ? title : URL.lastPathComponent;
    [self presentPlayerForURL:URL title:displayTitle referrerString:referrer resumeKey:URL.absoluteString startPosition:0.0 webView:self.host.browserWebView];
    return YES;
}

- (void)presentPlayerForURL:(NSURL *)URL
                      title:(NSString *)title
             referrerString:(NSString *)referrerString
                  resumeKey:(NSString *)resumeKey
              startPosition:(NSTimeInterval)startPosition
                    webView:(BrowserWebView *)webView {
    self.playerPresented = YES;
    NSLog(@"[Video] opening native player for %@ (referrer %@)", URL.absoluteString, referrerString ?: @"none");

    [webView pauseAllMediaPlayback];
    // Some players only start after the click that got us here has finished running.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [webView pauseAllMediaPlayback];
    });

    NSMutableDictionary<NSString *, NSString *> *headers = [NSMutableDictionary dictionary];
    NSString *userAgent = self.host.browserUserAgent;
    if (userAgent.length > 0) {
        headers[@"User-Agent"] = userAgent;
    }
    if (referrerString.length > 0) {
        headers[@"Referer"] = referrerString;
        NSString *origin = [self originForURLString:referrerString];
        if (origin.length > 0) {
            headers[@"Origin"] = origin;
        }
    }

    NSURL *siteURL = webView.request.URL ?: [NSURL URLWithString:referrerString ?: @""];
    NSString *subtitle = [[self class] siteNameForURL:siteURL ?: URL];
    BrowserPlayerViewController *player = [[BrowserPlayerViewController alloc] initWithURL:URL
                                                                                     title:title
                                                                                  subtitle:subtitle
                                                                            requestHeaders:headers
                                                                                   cookies:[self cookiesForURL:URL]];
    // Only for the stream the page's player was playing.
    NSString *preferredMaster = [self.pendingMediaPreferences[@"master"] isKindOfClass:[NSString class]] ? self.pendingMediaPreferences[@"master"] : nil;
    if ([preferredMaster isEqualToString:URL.absoluteString]) {
        player.mediaPreferences = self.pendingMediaPreferences;
    }
    self.pendingMediaPreferences = nil;
    if (self.pendingSubtitles.count > 0) {
        [player addPageSubtitles:self.pendingSubtitles videoDuration:self.pendingDuration];
    }
    self.pendingSubtitles = nil;
    BrowserLibraryStore *library = [BrowserLibraryStore sharedStore];
    NSString *URLString = URL.absoluteString;
    __weak typeof(self) weakSelf = self;
    player.resumePositionProvider = ^NSTimeInterval(NSTimeInterval duration) {
        // A position carried over from the page's own player wins over a saved one.
        if (startPosition > 5.0) {
            return startPosition;
        }
        if (duration <= 0.0) {
            return 0.0;
        }
        return [library resumePositionForKey:resumeKey duration:duration];
    };
    player.completionHandler = ^(NSTimeInterval position, NSTimeInterval duration, NSError *error) {
        weakSelf.playerPresented = NO;
        if (error != nil) {
            [weakSelf.failedURLStrings addObject:URLString];
            return;
        }
        if (duration > 0.0) {
            [library setResumePosition:position duration:duration forKey:resumeKey];
        }
    };
    [self.host browserPresentViewController:player];
}

@end
