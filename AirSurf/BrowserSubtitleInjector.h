#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Adds subtitles a web page's player had as separate files (WebVTT or SRT) to an HLS
/// stream as ordinary subtitle tracks, so they appear in the Apple TV player's subtitles
/// menu and follow the system caption style.
///
/// While it exists, a small HTTP server on 127.0.0.1 serves the stream's master playlist
/// (fetched once, every link made absolute, subtitle tracks added) and the subtitle files.
/// The video itself still loads straight from its own server.
@interface BrowserSubtitleInjector : NSObject

/// `subtitles`: dictionaries from the page agent with url, format ("vtt" / "srt"), label,
/// lang, showing, and optionally vtt (the cues the page already had, as WebVTT text).
- (instancetype)initWithStreamURL:(NSURL *)streamURL
                        subtitles:(NSArray<NSDictionary *> *)subtitles
                    videoDuration:(NSTimeInterval)duration
                   requestHeaders:(NSDictionary<NSString *, NSString *> *)headers
                          cookies:(NSArray<NSHTTPCookie *> *)cookies NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Only HLS streams can take extra tracks this way.
+ (BOOL)canInjectIntoURL:(NSURL *)URL;

/// The URL to open with AVURLAsset instead of the stream's own.
@property (nonatomic, readonly) NSURL *assetURL;
/// NO if the local server could not start; then play the stream without subtitles.
@property (nonatomic, readonly, getter=isServing) BOOL serving;
/// Title (HLS NAME) of the track that was on in the page, if one was.
@property (nonatomic, readonly, nullable) NSString *selectedTrackName;
@property (nonatomic, readonly) NSUInteger trackCount;

@end

NS_ASSUME_NONNULL_END
