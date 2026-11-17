#import <AVKit/AVKit.h>

NS_ASSUME_NONNULL_BEGIN

/// The system tvOS player, fed a stream found on a web page. All transport controls,
/// scrubbing, the info panel and audio/subtitle menus are AVKit's own.
@interface BrowserPlayerViewController : AVPlayerViewController

- (instancetype)initWithURL:(NSURL *)URL
                      title:(nullable NSString *)title
                   subtitle:(nullable NSString *)subtitle
             requestHeaders:(nullable NSDictionary<NSString *, NSString *> *)requestHeaders
                    cookies:(nullable NSArray<NSHTTPCookie *> *)cookies NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

/// Looked up once the duration is known; return a position to resume from, or 0.
@property (nonatomic, copy, nullable) NSTimeInterval (^resumePositionProvider)(NSTimeInterval duration);
/// What was picked in the page's own player, to carry over. Set before presenting.
///   level:    {width, height, bitrate, highest}  - caps quality unless it was the highest
///   audio:    {name, lang, index, count}         - voice-over
///   subtitle: {name, lang}
@property (nonatomic, copy, nullable) NSDictionary *mediaPreferences;
/// Subtitle files the page's player had (see BrowserSubtitleInjector). They are added to the
/// stream as subtitle tracks; the one that was on in the page is turned on. Before presenting.
- (void)addPageSubtitles:(NSArray<NSDictionary *> *)subtitles videoDuration:(NSTimeInterval)duration;
/// Called when the player goes away. `error` is set if the stream never played.
@property (nonatomic, copy, nullable) void (^completionHandler)(NSTimeInterval position, NSTimeInterval duration, NSError * _Nullable error);

@end

NS_ASSUME_NONNULL_END
