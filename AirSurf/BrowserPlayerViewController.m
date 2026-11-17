#import "BrowserPlayerViewController.h"

#import <AVFoundation/AVFoundation.h>

#import "BrowserSubtitleInjector.h"
#import "BrowserTheme.h"

static void *kPlayerItemStatusContext = &kPlayerItemStatusContext;

#if DEBUG
@interface BrowserPlayerViewController () <AVPlayerItemLegibleOutputPushDelegate>
@end
#endif

@interface BrowserPlayerViewController ()

@property (nonatomic, strong) NSURL *videoURL;
@property (nonatomic, copy) NSString *videoTitle;
@property (nonatomic, copy) NSString *videoSubtitle;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *requestHeaders;
@property (nonatomic, copy) NSArray<NSHTTPCookie *> *requestCookies;
@property (nonatomic, strong) AVPlayerItem *observedItem;
@property (nonatomic, strong) NSError *playbackError;
@property (nonatomic) BOOL didBecomeReady;
@property (nonatomic) BOOL didReportCompletion;
@property (nonatomic) BOOL didStartPlayback;
@property (nonatomic) UILabel *noticeLabel;
@property (nonatomic, copy) NSArray<NSDictionary *> *pageSubtitles;
@property (nonatomic) NSTimeInterval pageVideoDuration;
@property (nonatomic, strong) BrowserSubtitleInjector *subtitleInjector;

@end

@implementation BrowserPlayerViewController

- (instancetype)initWithURL:(NSURL *)URL
                      title:(NSString *)title
                   subtitle:(NSString *)subtitle
             requestHeaders:(NSDictionary<NSString *, NSString *> *)requestHeaders
                    cookies:(NSArray<NSHTTPCookie *> *)cookies {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _videoURL = URL;
        _videoTitle = [title copy] ?: @"";
        _videoSubtitle = [subtitle copy] ?: @"";
        _requestHeaders = [requestHeaders copy] ?: @{};
        _requestCookies = [cookies copy] ?: @[];
        self.modalPresentationStyle = UIModalPresentationFullScreen;
    }
    return self;
}

- (AVMetadataItem *)metadataItemWithIdentifier:(AVMetadataIdentifier)identifier value:(NSString *)value {
    AVMutableMetadataItem *item = [AVMutableMetadataItem metadataItem];
    item.identifier = identifier;
    item.value = value;
    item.extendedLanguageTag = @"und";
    return [item copy];
}

- (void)addPageSubtitles:(NSArray<NSDictionary *> *)subtitles videoDuration:(NSTimeInterval)duration {
    self.pageSubtitles = subtitles;
    self.pageVideoDuration = duration;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;

    BOOL addSubtitles = self.pageSubtitles.count > 0 && [BrowserSubtitleInjector canInjectIntoURL:self.videoURL];
    AVPlayer *player = [AVPlayer playerWithPlayerItem:[self makePlayerItemAddingSubtitles:addSubtitles]];
    player.allowsExternalPlayback = YES;
    self.player = player;

    self.noticeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.noticeLabel.font = [UIFont systemFontOfSize:29.0 weight:UIFontWeightSemibold];
    self.noticeLabel.textColor = UIColor.whiteColor;
    self.noticeLabel.textAlignment = NSTextAlignmentCenter;
    self.noticeLabel.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.62];
    self.noticeLabel.layer.cornerRadius = 32.0;
    self.noticeLabel.layer.cornerCurve = kCACornerCurveContinuous;
    self.noticeLabel.clipsToBounds = YES;
    self.noticeLabel.alpha = 0.0;
    [self.contentOverlayView addSubview:self.noticeLabel];
}

- (AVPlayerItem *)makePlayerItemAddingSubtitles:(BOOL)addSubtitles {
    // Streams found on a page usually only answer requests that look like they come from
    // that page: same Referer, Origin, User-Agent and cookies.
    NSMutableDictionary *assetOptions = [NSMutableDictionary dictionary];
    if (self.requestHeaders.count > 0) {
        assetOptions[@"AVURLAssetHTTPHeaderFieldsKey"] = self.requestHeaders;
        NSString *userAgent = self.requestHeaders[@"User-Agent"];
        if (userAgent.length > 0) {
            assetOptions[@"AVURLAssetHTTPUserAgentKey"] = userAgent;
        }
    }
    if (self.requestCookies.count > 0) {
        assetOptions[AVURLAssetHTTPCookiesKey] = self.requestCookies;
    }
    AVURLAsset *asset = nil;
    self.subtitleInjector = nil;
    if (addSubtitles) {
        BrowserSubtitleInjector *injector = [[BrowserSubtitleInjector alloc] initWithStreamURL:self.videoURL
                                                                                     subtitles:self.pageSubtitles
                                                                                 videoDuration:self.pageVideoDuration
                                                                                requestHeaders:self.requestHeaders
                                                                                       cookies:self.requestCookies];
        self.subtitleInjector = (injector.serving && injector.trackCount > 0) ? injector : nil;
    }
    if (self.subtitleInjector != nil) {
        asset = [AVURLAsset URLAssetWithURL:self.subtitleInjector.assetURL options:assetOptions];
        NSString *selected = self.subtitleInjector.selectedTrackName;
        if (selected.length > 0 && self.mediaPreferences[@"subtitle"] == nil) {
            NSMutableDictionary *preferences = [self.mediaPreferences mutableCopy] ?: [NSMutableDictionary dictionary];
            preferences[@"subtitle"] = @{@"name": selected};
            self.mediaPreferences = preferences;
        }
    } else {
        asset = [AVURLAsset URLAssetWithURL:self.videoURL options:assetOptions];
    }
    AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:asset];

    NSMutableArray<AVMetadataItem *> *metadata = [NSMutableArray array];
    if (self.videoTitle.length > 0) {
        [metadata addObject:[self metadataItemWithIdentifier:AVMetadataCommonIdentifierTitle value:self.videoTitle]];
    }
    if (self.videoSubtitle.length > 0) {
        [metadata addObject:[self metadataItemWithIdentifier:AVMetadataIdentifieriTunesMetadataTrackSubTitle value:self.videoSubtitle]];
    }
    item.externalMetadata = metadata;

    self.observedItem = item;
    [item addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:kPlayerItemStatusContext];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleItemFailedToPlayToEnd:)
                                                 name:AVPlayerItemFailedToPlayToEndTimeNotification
                                               object:item];

    [self applyQualityPreferenceToItem:item];
#if DEBUG
    // Logs each subtitle as it is shown, with the player's clock, to check timing.
    AVPlayerItemLegibleOutput *legible = [[AVPlayerItemLegibleOutput alloc] init];
    [legible setDelegate:self queue:dispatch_get_main_queue()];
    [item addOutput:legible];
#endif
    return item;
}

#if DEBUG
- (void)legibleOutput:(AVPlayerItemLegibleOutput *)output didOutputAttributedStrings:(NSArray<NSAttributedString *> *)strings
  nativeSampleBuffers:(NSArray *)nativeSamples forItemTime:(CMTime)itemTime {
    if (strings.count > 0) {
        NSLog(@"[Player] cue \"%@\" at %.2f s", [strings.firstObject.string stringByReplacingOccurrencesOfString:@"\n" withString:@" / "], CMTimeGetSeconds(itemTime));
    }
}
#endif

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.didStartPlayback) {
        self.didStartPlayback = YES;
        [self.player play];
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (self.isBeingDismissed || self.presentingViewController == nil) {
        [self.player pause];
        [self reportCompletion];
    }
}

- (void)dealloc {
    [self stopObserving];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)stopObserving {
    if (self.observedItem != nil) {
        @try {
            [self.observedItem removeObserver:self forKeyPath:@"status" context:kPlayerItemStatusContext];
        } @catch (__unused NSException *exception) {}
        self.observedItem = nil;
    }
}

- (NSTimeInterval)currentPosition {
    NSTimeInterval position = CMTimeGetSeconds(self.player.currentTime);
    return isfinite(position) ? position : 0.0;
}

- (NSTimeInterval)currentDuration {
    NSTimeInterval duration = CMTimeGetSeconds(self.player.currentItem.duration);
    return isfinite(duration) ? duration : 0.0;
}

- (void)reportCompletion {
    if (self.didReportCompletion) {
        return;
    }
    self.didReportCompletion = YES;
    NSTimeInterval position = [self currentPosition];
    NSTimeInterval duration = [self currentDuration];
    void (^handler)(NSTimeInterval, NSTimeInterval, NSError *) = self.completionHandler;
    self.completionHandler = nil;
    if (handler != nil) {
        handler(position, duration, self.didBecomeReady ? nil : self.playbackError);
    }
}

#pragma mark Status

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey, id> *)change context:(void *)context {
    if (context != kPlayerItemStatusContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [self handleItemStatusChange];
    });
}

- (void)handleItemStatusChange {
    AVPlayerItem *item = self.player.currentItem;
    if (item.status == AVPlayerItemStatusReadyToPlay && !self.didBecomeReady) {
        self.didBecomeReady = YES;
        [self applyTrackPreferencesToItem:item];
        NSTimeInterval duration = [self currentDuration];
        NSTimeInterval resumePosition = self.resumePositionProvider != nil ? self.resumePositionProvider(duration) : 0.0;
        if (resumePosition > 1.0 && (duration <= 0.0 || resumePosition < duration - 5.0)) {
            [self.player seekToTime:CMTimeMakeWithSeconds(resumePosition, NSEC_PER_SEC)
                    toleranceBefore:CMTimeMakeWithSeconds(2.0, NSEC_PER_SEC)
                     toleranceAfter:CMTimeMakeWithSeconds(2.0, NSEC_PER_SEC)];
            [self showNotice:[NSString stringWithFormat:@"Resumed from %@", [self timeStringForSeconds:resumePosition]]];
        }
    } else if (item.status == AVPlayerItemStatusFailed) {
        [self failWithError:item.error];
    }
}

- (void)handleItemFailedToPlayToEnd:(NSNotification *)notification {
    NSError *error = notification.userInfo[AVPlayerItemFailedToPlayToEndTimeErrorKey];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self failWithError:error];
    });
}

- (void)failWithError:(NSError *)error {
    if (self.playbackError != nil) {
        return;
    }
    if (self.subtitleInjector != nil) {
        // Whatever went wrong with the added subtitles, the video still comes first: carry on
        // from the same place without them.
        NSLog(@"[Subtitles] Stream failed with added subtitles (%@); playing it without them", error);
#if DEBUG
        for (AVPlayerItemErrorLogEvent *event in self.player.currentItem.errorLog.events) {
            NSLog(@"[Subtitles] error log: %ld %@ %@ %@", (long)event.errorStatusCode, event.errorDomain, event.errorComment, event.URI);
        }
#endif
        NSTimeInterval position = [self currentPosition];
        [self stopObserving];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemFailedToPlayToEndTimeNotification object:nil];
        if (self.didBecomeReady && position > 1.0) {
            self.didBecomeReady = NO;
            NSTimeInterval (^previous)(NSTimeInterval) = self.resumePositionProvider;
            self.resumePositionProvider = ^NSTimeInterval(NSTimeInterval duration) {
                return position > 1.0 ? position : (previous != nil ? previous(duration) : 0.0);
            };
        }
        [self.player replaceCurrentItemWithPlayerItem:[self makePlayerItemAddingSubtitles:NO]];
        [self.player play];
        return;
    }
    self.playbackError = error ?: [NSError errorWithDomain:AVFoundationErrorDomain code:AVErrorUnknown userInfo:nil];
    NSLog(@"[Browser] Native playback failed for %@: %@", self.videoURL.host, self.playbackError);
    if (self.presentedViewController != nil || self.view.window == nil) {
        return;
    }
    NSString *message = self.playbackError.localizedDescription ?: @"The stream could not be opened.";
    NSString *reason = self.playbackError.localizedFailureReason;
    if (reason.length > 0) {
        message = [message stringByAppendingFormat:@"\n%@", reason];
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"This Video Can’t Be Played Here"
                                                                   message:[message stringByAppendingString:@"\n\nYou can still watch it in the page."]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Back to Page" style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *action) {
        [weakSelf dismissViewControllerAnimated:YES completion:nil];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark Carrying over the page's choices

static NSDictionary *BrowserDictionary(id value) {
    return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

static NSString *BrowserTrimmedString(id value) {
    return [value isKindOfClass:[NSString class]] ? [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"";
}

- (void)applyQualityPreferenceToItem:(AVPlayerItem *)item {
    NSDictionary *level = BrowserDictionary(self.mediaPreferences[@"level"]);
    if (level == nil || [level[@"highest"] boolValue]) {
        return;
    }
    // A lower quality picked on purpose (a slow connection, say) stays the ceiling here too.
    double width = [level[@"width"] doubleValue];
    double height = [level[@"height"] doubleValue];
    double bitrate = [level[@"bitrate"] doubleValue];
    if (width > 0.0 && height > 0.0) {
        item.preferredMaximumResolution = CGSizeMake(width, height);
    }
    if (bitrate > 0.0) {
        item.preferredPeakBitRate = bitrate * 1.1;
    }
}

- (AVMediaSelectionOption *)optionInGroup:(AVMediaSelectionGroup *)group matching:(NSDictionary *)preference {
    NSString *name = BrowserTrimmedString(preference[@"name"]);
    NSString *language = BrowserTrimmedString(preference[@"lang"]).lowercaseString;
    for (AVMediaSelectionOption *option in group.options) {
        // HLS keeps a rendition's NAME as its title; displayName is built from the language.
        NSString *title = [AVMetadataItem metadataItemsFromArray:option.commonMetadata filteredByIdentifier:AVMetadataCommonIdentifierTitle].firstObject.stringValue;
        if (name.length > 0 && ([option.displayName caseInsensitiveCompare:name] == NSOrderedSame ||
                                (title.length > 0 && [title caseInsensitiveCompare:name] == NSOrderedSame))) {
            return option;
        }
    }
    for (AVMediaSelectionOption *option in group.options) {
        NSString *tag = option.extendedLanguageTag.lowercaseString ?: option.locale.languageCode.lowercaseString;
        if (language.length > 0 && tag.length > 0 && ([tag isEqualToString:language] || [tag hasPrefix:[language stringByAppendingString:@"-"]])) {
            return option;
        }
    }
    // Same number of tracks as the page listed: they are the same tracks in the same order.
    NSInteger index = [preference[@"index"] respondsToSelector:@selector(integerValue)] ? [preference[@"index"] integerValue] : -1;
    NSInteger count = [preference[@"count"] respondsToSelector:@selector(integerValue)] ? [preference[@"count"] integerValue] : 0;
    if (index >= 0 && count == (NSInteger)group.options.count && index < count) {
        return group.options[index];
    }
    return nil;
}

- (void)applyTrackPreferencesToItem:(AVPlayerItem *)item {
    NSDictionary *audio = BrowserDictionary(self.mediaPreferences[@"audio"]);
    NSDictionary *subtitle = BrowserDictionary(self.mediaPreferences[@"subtitle"]);
    if (audio == nil && subtitle == nil) {
        return;
    }
    __weak AVPlayerItem *weakItem = item;
    void (^select)(AVMediaCharacteristic, NSDictionary *) = ^(AVMediaCharacteristic characteristic, NSDictionary *preference) {
        [item.asset loadMediaSelectionGroupForMediaCharacteristic:characteristic completionHandler:^(AVMediaSelectionGroup *group, NSError *error) {
            AVMediaSelectionOption *option = group != nil ? [self optionInGroup:group matching:preference] : nil;
#if DEBUG
            for (AVMediaSelectionOption *candidate in group.options) {
                NSLog(@"[Player] %@ option displayName=%@ tag=%@ title=%@ characteristics=%@", characteristic, candidate.displayName, candidate.extendedLanguageTag,
                      [AVMetadataItem metadataItemsFromArray:candidate.commonMetadata filteredByIdentifier:AVMetadataCommonIdentifierTitle].firstObject.stringValue,
                      [candidate hasMediaCharacteristic:AVMediaCharacteristicTranscribesSpokenDialogForAccessibility] ? @"SDH" : @"-");
            }
            NSLog(@"[Player] %@ -> %@", characteristic, option.displayName);
#endif
            if (option == nil) {
                return;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakItem selectMediaOption:option inMediaSelectionGroup:group];
            });
        }];
    };
    if (audio != nil) {
        select(AVMediaCharacteristicAudible, audio);
    }
    if (subtitle != nil) {
        select(AVMediaCharacteristicLegible, subtitle);
    }
}

#pragma mark Notice

- (NSString *)timeStringForSeconds:(NSTimeInterval)seconds {
    NSInteger total = (NSInteger)llround(seconds);
    NSInteger hours = total / 3600;
    NSInteger minutes = (total % 3600) / 60;
    NSInteger remainder = total % 60;
    if (hours > 0) {
        return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)hours, (long)minutes, (long)remainder];
    }
    return [NSString stringWithFormat:@"%ld:%02ld", (long)minutes, (long)remainder];
}

- (void)showNotice:(NSString *)text {
    self.noticeLabel.text = text;
    CGSize size = [self.noticeLabel sizeThatFits:CGSizeMake(900.0, 64.0)];
    CGRect bounds = self.contentOverlayView.bounds;
    self.noticeLabel.frame = CGRectMake(floor((CGRectGetWidth(bounds) - size.width - 64.0) / 2.0), 90.0, size.width + 64.0, 64.0);
    [BrowserTheme animate:^{
        self.noticeLabel.alpha = 1.0;
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [BrowserTheme animate:^{
            self.noticeLabel.alpha = 0.0;
        }];
    });
}

@end
