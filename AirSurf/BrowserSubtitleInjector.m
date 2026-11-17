#import "BrowserSubtitleInjector.h"

#import <arpa/inet.h>
#import <netinet/in.h>
#import <sys/socket.h>
#import <unistd.h>

static NSString * const kGroupID = @"tvbsubs";

@interface BrowserSubtitleTrack : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *language;
@property (nonatomic, copy) NSString *format;
@property (nonatomic, strong, nullable) NSURL *fileURL;
@property (nonatomic, copy, nullable) NSString *inlineText;
@property (nonatomic, copy) NSString *label;
@property (nonatomic) BOOL showing;
@end

@implementation BrowserSubtitleTrack
@end

@interface BrowserSubtitleInjector ()

@property (nonatomic, strong) NSURL *streamURL;
@property (nonatomic, copy) NSArray<BrowserSubtitleTrack *> *tracks;
@property (nonatomic) NSTimeInterval duration;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *headers;
@property (nonatomic, copy) NSArray<NSHTTPCookie *> *cookies;
/// Responses already built, by request path. Guarded by `lock`.
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSData *> *responseCache;
@property (nonatomic, strong) NSLock *lock;
/// Random first path component, so only this player's requests are answered.
@property (nonatomic, copy) NSString *pathPrefix;
@property (nonatomic) int listenSocket;
@property (nonatomic, strong, nullable) dispatch_source_t acceptSource;
/// A media playlist of the stream, read to find where its timestamps start.
@property (nonatomic, strong, nullable) NSURL *probeURL;
/// Stream start in 90 kHz ticks; nil until probed.
@property (nonatomic, strong, nullable) NSNumber *startTicks;

@end

@implementation BrowserSubtitleInjector

+ (BOOL)canInjectIntoURL:(NSURL *)URL {
    NSString *scheme = URL.scheme.lowercaseString;
    if (!([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])) {
        return NO;
    }
    return [URL.pathExtension.lowercaseString isEqualToString:@"m3u8"] ||
           [URL.absoluteString.lowercaseString containsString:@"m3u8"];
}

- (instancetype)initWithStreamURL:(NSURL *)streamURL
                        subtitles:(NSArray<NSDictionary *> *)subtitles
                    videoDuration:(NSTimeInterval)duration
                   requestHeaders:(NSDictionary<NSString *, NSString *> *)headers
                          cookies:(NSArray<NSHTTPCookie *> *)cookies {
    self = [super init];
    if (self) {
        _streamURL = streamURL;
        _duration = duration;
        _headers = [headers copy] ?: @{};
        _cookies = [cookies copy] ?: @[];
        _responseCache = [NSMutableDictionary dictionary];
        _lock = [NSLock new];
        _listenSocket = -1;
        _pathPrefix = [[NSUUID UUID].UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""].lowercaseString;

        NSMutableArray<BrowserSubtitleTrack *> *tracks = [NSMutableArray array];
        NSMutableSet<NSString *> *names = [NSMutableSet set];
        for (NSDictionary *entry in subtitles) {
            if (![entry isKindOfClass:[NSDictionary class]]) {
                continue;
            }
            NSString *label = [self stringIn:entry key:@"label"];
            NSString *URLString = [self stringIn:entry key:@"url"];
            NSString *inlineText = [self stringIn:entry key:@"vtt"];
            NSURL *fileURL = URLString.length > 0 ? [NSURL URLWithString:URLString] : nil;
            if (fileURL == nil && inlineText.length == 0) {
                continue;
            }
            BrowserSubtitleTrack *track = [BrowserSubtitleTrack new];
            NSString *name = [[self class] displayNameForLabel:label index:tracks.count];
            NSString *uniqueName = name;
            for (NSUInteger copy = 2; [names containsObject:uniqueName]; copy++) {
                uniqueName = [NSString stringWithFormat:@"%@ %lu", name, (unsigned long)copy];
            }
            [names addObject:uniqueName];
            track.name = uniqueName;
            track.label = label;
            NSString *language = [self stringIn:entry key:@"lang"];
            track.language = language.length > 0 ? language : [[self class] languageCodeForLabel:label];
            track.format = [[self stringIn:entry key:@"format"] isEqualToString:@"srt"] ? @"srt" : @"vtt";
            track.fileURL = fileURL;
            track.inlineText = inlineText.length > 0 ? inlineText : nil;
            track.showing = [entry[@"showing"] respondsToSelector:@selector(boolValue)] && [entry[@"showing"] boolValue];
            if (track.showing && _selectedTrackName == nil) {
                _selectedTrackName = track.name;
            }
            [tracks addObject:track];
        }
        _tracks = [[self class] menuTracksFrom:tracks];

        uint16_t port = [self startServer];
        _assetURL = port > 0
            ? [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%u/%@/stream.m3u8", port, _pathPrefix]]
            : streamURL;
    }
    return self;
}

- (void)dealloc {
    [self stopServer];
}

- (BOOL)isServing {
    return self.listenSocket >= 0;
}

- (NSUInteger)trackCount {
    return self.tracks.count;
}

- (NSString *)stringIn:(NSDictionary *)dictionary key:(NSString *)key {
    id value = dictionary[key];
    return [value isKindOfClass:[NSString class]] ? [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"";
}

#pragma mark Choosing tracks

+ (BOOL)label:(NSString *)label matches:(NSString *)pattern {
    return [label rangeOfString:pattern options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location != NSNotFound;
}

/// Lower is better for the one track a language gets in the menu.
+ (NSInteger)rankForLabel:(NSString *)label {
    if ([self label:label matches:@"forced|форс"]) {
        return 3;   // only the foreign-language lines
    }
    if ([self label:label matches:@"comment|коммент"]) {
        return 4;
    }
    if ([self label:label matches:@"sdh|hearing|глух|cc\\b"]) {
        return 1;
    }
    return 0;
}

/// The Apple TV subtitles menu names tracks by language only, so six Russian tracks would
/// read "Russian" six times. Each language gets one track: the one that was on in the page,
/// otherwise its most complete ordinary one.
+ (NSArray<BrowserSubtitleTrack *> *)menuTracksFrom:(NSArray<BrowserSubtitleTrack *> *)tracks {
    NSMutableDictionary<NSString *, BrowserSubtitleTrack *> *chosen = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *order = [NSMutableArray array];
    for (BrowserSubtitleTrack *track in tracks) {
        NSString *key = [track.language isEqualToString:@"und"] ? track.name : track.language;
        BrowserSubtitleTrack *current = chosen[key];
        if (current == nil) {
            [order addObject:key];
            chosen[key] = track;
            continue;
        }
        if (current.showing) {
            continue;
        }
        if (track.showing || [self rankForLabel:track.label] < [self rankForLabel:current.label] ||
            ([self rankForLabel:track.label] == [self rankForLabel:current.label] && [self label:track.label matches:@"full|полн"])) {
            chosen[key] = track;
        }
    }
    NSMutableArray<BrowserSubtitleTrack *> *result = [NSMutableArray array];
    for (NSString *key in order) {
        [result addObject:chosen[key]];
    }
    return result;
}

#pragma mark Names and languages

/// "(English) SDH" -> "English (SDH)"; "(Russian) full" -> "Russian (full)".
+ (NSString *)displayNameForLabel:(NSString *)label index:(NSUInteger)index {
    NSString *trimmed = [label stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        return [NSString stringWithFormat:@"Subtitles %lu", (unsigned long)index + 1];
    }
    NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:@"^\\(([^)]+)\\)\\s*(.*)$" options:0 error:nil];
    NSTextCheckingResult *match = [expression firstMatchInString:trimmed options:0 range:NSMakeRange(0, trimmed.length)];
    if (match != nil) {
        NSString *language = [trimmed substringWithRange:[match rangeAtIndex:1]];
        NSString *rest = [trimmed substringWithRange:[match rangeAtIndex:2]];
        trimmed = rest.length > 0 ? [NSString stringWithFormat:@"%@ (%@)", language, rest] : language;
    }
    // Quotes would end the NAME attribute in the playlist.
    return [trimmed stringByReplacingOccurrencesOfString:@"\"" withString:@"'"];
}

+ (NSString *)languageCodeForLabel:(NSString *)label {
    NSString *lower = label.lowercaseString;
    NSArray<NSArray<NSString *> *> *table = @[
        @[@"ru", @"russian", @"русск"], @[@"en", @"english", @"англ"], @[@"uk", @"ukrainian", @"украин"],
        @[@"de", @"german", @"немец"], @[@"fr", @"french", @"француз"], @[@"es", @"spanish", @"испан"],
        @[@"it", @"italian", @"итальян"], @[@"pt", @"portuguese", @"португал"], @[@"pl", @"polish", @"польск"],
        @[@"tr", @"turkish", @"турец"], @[@"ja", @"japanese", @"японск"], @[@"ko", @"korean", @"корейск"],
        @[@"zh", @"chinese", @"китайск"], @[@"kk", @"kazakh", @"казах"], @[@"be", @"belarusian", @"белорус"],
    ];
    for (NSArray<NSString *> *row in table) {
        if ([lower containsString:row[1]] || [lower containsString:row[2]]) {
            return row[0];
        }
    }
    return @"und";
}

#pragma mark Playlists

- (NSString *)localPath:(NSString *)name {
    return [NSString stringWithFormat:@"/%@/%@", self.pathPrefix, name];
}

- (NSString *)mediaLines {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    [self.tracks enumerateObjectsUsingBlock:^(BrowserSubtitleTrack *track, NSUInteger index, BOOL *stop) {
        // SDH tracks say so in the menu through the standard accessibility characteristics.
        NSString *characteristics = [[self class] rankForLabel:track.label] == 1
            ? @",CHARACTERISTICS=\"public.accessibility.transcribes-spoken-dialog,public.accessibility.describes-music-and-sound\"" : @"";
        [lines addObject:[NSString stringWithFormat:@"#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID=\"%@\",NAME=\"%@\",LANGUAGE=\"%@\",DEFAULT=%@,AUTOSELECT=YES,FORCED=NO%@,URI=\"%@\"",
                          kGroupID, track.name, track.language, [track.name isEqualToString:self.selectedTrackName] ? @"YES" : @"NO",
                          characteristics, [self localPath:[NSString stringWithFormat:@"subtitles-%lu.m3u8", (unsigned long)index]]]];
    }];
    return [lines componentsJoinedByString:@"\n"];
}

- (NSString *)line:(NSString *)line resolvingURIAgainst:(NSURL *)base {
    NSRange start = [line rangeOfString:@"URI=\""];
    if (start.location == NSNotFound) {
        return line;
    }
    NSUInteger valueStart = NSMaxRange(start);
    NSRange end = [line rangeOfString:@"\"" options:0 range:NSMakeRange(valueStart, line.length - valueStart)];
    if (end.location == NSNotFound) {
        return line;
    }
    NSString *value = [line substringWithRange:NSMakeRange(valueStart, end.location - valueStart)];
    NSString *absolute = [NSURL URLWithString:value relativeToURL:base].absoluteString;
    if (absolute.length == 0) {
        return line;
    }
    return [line stringByReplacingCharactersInRange:NSMakeRange(valueStart, end.location - valueStart) withString:absolute];
}

/// The stream's playlist with every link absolute and the page's subtitles added.
- (NSString *)playlistByAddingSubtitlesTo:(NSString *)text baseURL:(NSURL *)base {
    BOOL isMaster = [text containsString:@"#EXT-X-STREAM-INF"];
    NSString *media = [self mediaLines];
    if (!isMaster) {
        // A single-quality stream: wrap it in a master playlist so it can carry tracks.
        return [@[@"#EXTM3U", media,
                  [NSString stringWithFormat:@"#EXT-X-STREAM-INF:BANDWIDTH=4000000,SUBTITLES=\"%@\"", kGroupID],
                  base.absoluteString, @""] componentsJoinedByString:@"\n"];
    }
    // A stream that has its own subtitle tracks keeps them; the player shows those already.
    BOOL addTracks = ![text containsString:@"TYPE=SUBTITLES"];
    BOOL inserted = NO;
    NSMutableArray<NSString *> *output = [NSMutableArray array];
    for (NSString *rawLine in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *line = [rawLine stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (line.length == 0) {
            continue;
        }
        if ([line hasPrefix:@"#"]) {
            line = [self line:line resolvingURIAgainst:base];
            if (addTracks && [line hasPrefix:@"#EXT-X-STREAM-INF:"]) {
                if (!inserted) {
                    [output addObject:media];
                    inserted = YES;
                }
                line = [line stringByAppendingFormat:@",SUBTITLES=\"%@\"", kGroupID];
            }
            [output addObject:line];
        } else {
            NSString *absolute = [NSURL URLWithString:line relativeToURL:base].absoluteString;
            [output addObject:absolute.length > 0 ? absolute : line];
        }
    }
    [output addObject:@""];
    return [output componentsJoinedByString:@"\n"];
}

/// The whole file as one segment lasting the whole video.
- (NSString *)subtitlePlaylistForTrackAtIndex:(NSUInteger)index {
    NSTimeInterval duration = self.duration > 1.0 ? self.duration : 6.0 * 3600.0;
    return [@[@"#EXTM3U",
              @"#EXT-X-VERSION:3",
              [NSString stringWithFormat:@"#EXT-X-TARGETDURATION:%ld", (long)ceil(duration)],
              @"#EXT-X-MEDIA-SEQUENCE:0",
              @"#EXT-X-PLAYLIST-TYPE:VOD",
              [NSString stringWithFormat:@"#EXTINF:%.3f,", duration],
              [self localPath:[NSString stringWithFormat:@"subtitles-%lu.vtt", (unsigned long)index]],
              @"#EXT-X-ENDLIST", @""] componentsJoinedByString:@"\n"];
}

+ (NSString *)webVTTFromText:(NSString *)text format:(NSString *)format {
    NSString *body = [text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
    if ([body hasPrefix:@"﻿"]) {
        body = [body substringFromIndex:1];
    }
    if ([body hasPrefix:@"WEBVTT"]) {
        return body;
    }
    if ([format isEqualToString:@"srt"] || [body rangeOfString:@"-->"].location != NSNotFound) {
        // SRT writes 00:00:01,500 where WebVTT writes 00:00:01.500.
        NSRegularExpression *comma = [NSRegularExpression regularExpressionWithPattern:@"(\\d{2}:\\d{2}:\\d{2}),(\\d{3})" options:0 error:nil];
        body = [comma stringByReplacingMatchesInString:body options:0 range:NSMakeRange(0, body.length) withTemplate:@"$1.$2"];
    }
    return [@"WEBVTT\n\n" stringByAppendingString:body];
}

#pragma mark Fetching

- (NSMutableURLRequest *)requestForURL:(NSURL *)URL {
    return [self requestForURL:URL maximumLength:0];
}

- (NSMutableURLRequest *)requestForURL:(NSURL *)URL maximumLength:(NSUInteger)maximumLength {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:URL];
    request.timeoutInterval = 15.0;
    if (maximumLength > 0) {
        [request setValue:[NSString stringWithFormat:@"bytes=0-%lu", (unsigned long)maximumLength - 1] forHTTPHeaderField:@"Range"];
    }
    [self.headers enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        [request setValue:value forHTTPHeaderField:key];
    }];
    NSDictionary<NSString *, NSString *> *cookieHeaders = [NSHTTPCookie requestHeaderFieldsWithCookies:self.cookies];
    [cookieHeaders enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        [request setValue:value forHTTPHeaderField:key];
    }];
    return request;
}

/// Runs on a client's background queue, so waiting here blocks nothing else.
- (NSData *)fetchURL:(NSURL *)URL status:(NSInteger *)statusOut finalURL:(NSURL **)finalURLOut {
    return [self fetchURL:URL maximumLength:0 status:statusOut finalURL:finalURLOut];
}

- (NSData *)fetchURL:(NSURL *)URL maximumLength:(NSUInteger)maximumLength status:(NSInteger *)statusOut finalURL:(NSURL **)finalURLOut {
    __block NSData *result = nil;
    __block NSInteger status = 0;
    __block NSURL *finalURL = URL;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [[[NSURLSession sharedSession] dataTaskWithRequest:[self requestForURL:URL maximumLength:maximumLength] completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        status = [response isKindOfClass:[NSHTTPURLResponse class]] ? ((NSHTTPURLResponse *)response).statusCode : (error != nil ? 0 : 200);
        finalURL = response.URL ?: URL;
        result = (error == nil && status < 400) ? data : nil;
        dispatch_semaphore_signal(done);
    }] resume];
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20 * NSEC_PER_SEC)));
    if (statusOut != NULL) {
        *statusOut = status;
    }
    if (finalURLOut != NULL) {
        *finalURLOut = finalURL;
    }
    return result;
}

/// Body and content type for a path, or nil body with an HTTP status.
- (NSData *)responseForPath:(NSString *)path contentType:(NSString **)contentType status:(NSInteger *)status {
    *status = 200;
    NSString *prefix = [NSString stringWithFormat:@"/%@/", self.pathPrefix];
    if (![path hasPrefix:prefix]) {
        *status = 404;
        return nil;
    }
    NSString *name = [path substringFromIndex:prefix.length];
    BOOL isPlaylist = [name hasSuffix:@".m3u8"];
    *contentType = isPlaylist ? @"application/vnd.apple.mpegurl" : @"text/vtt; charset=utf-8";

    [self.lock lock];
    NSData *cached = self.responseCache[name];
    [self.lock unlock];
    if (cached != nil) {
        return cached;
    }

    NSData *body = nil;
    if ([name isEqualToString:@"stream.m3u8"]) {
        NSInteger upstreamStatus = 0;
        NSURL *finalURL = nil;
        NSData *data = [self fetchURL:self.streamURL status:&upstreamStatus finalURL:&finalURL];
        NSString *text = data.length > 0 ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
        if (text == nil) {
            NSLog(@"[Subtitles] Stream playlist failed (HTTP %ld)", (long)upstreamStatus);
            *status = upstreamStatus >= 400 ? upstreamStatus : 502;
            return nil;
        }
        NSURL *base = finalURL ?: self.streamURL;
        NSString *playlist = [text hasPrefix:@"#EXTM3U"] ? [self playlistByAddingSubtitlesTo:text baseURL:base] : text;
        [self.lock lock];
        self.probeURL = [text containsString:@"#EXT-X-STREAM-INF"] ? [self firstVariantURLIn:text base:base] : base;
        [self.lock unlock];
#if DEBUG
        NSLog(@"[Subtitles] Serving stream playlist with %lu added tracks:\n%@", (unsigned long)self.tracks.count,
              playlist.length > 1500 ? [playlist substringToIndex:1500] : playlist);
#endif
        body = [playlist dataUsingEncoding:NSUTF8StringEncoding];
    } else if ([name hasPrefix:@"subtitles-"]) {
        NSUInteger index = (NSUInteger)[[name substringFromIndex:10].stringByDeletingPathExtension integerValue];
        if (index >= self.tracks.count) {
            *status = 404;
            return nil;
        }
        BrowserSubtitleTrack *track = self.tracks[index];
        if (isPlaylist) {
            body = [[self subtitlePlaylistForTrackAtIndex:index] dataUsingEncoding:NSUTF8StringEncoding];
        } else if (track.inlineText.length > 0) {
            body = [[self timedWebVTT:[[self class] webVTTFromText:track.inlineText format:@"vtt"]] dataUsingEncoding:NSUTF8StringEncoding];
        } else {
            NSInteger upstreamStatus = 0;
            NSData *data = track.fileURL != nil ? [self fetchURL:track.fileURL status:&upstreamStatus finalURL:NULL] : nil;
            NSString *text = data.length > 0 ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
            if (text == nil && data.length > 0) {
                text = [[NSString alloc] initWithData:data encoding:NSWindowsCP1251StringEncoding];
            }
            if (text.length == 0) {
                // A file that will not load becomes an empty track rather than a broken player.
                NSLog(@"[Subtitles] \"%@\" could not be loaded (HTTP %ld)", track.name, (long)upstreamStatus);
            }
            body = [(text.length > 0 ? [self timedWebVTT:[[self class] webVTTFromText:text format:track.format]] : @"WEBVTT\n\n") dataUsingEncoding:NSUTF8StringEncoding];
        }
    } else {
        *status = 404;
        return nil;
    }
    [self.lock lock];
    self.responseCache[name] = body;
    [self.lock unlock];
    return body;
}

#pragma mark Timing

// The page's cue times count from the start of the video. HLS reads WebVTT times against the
// stream's own timestamps, which often start at 10 s or so, unless the file maps them with
// X-TIMESTAMP-MAP. The start is read from the first segment of the stream.

- (NSURL *)firstVariantURLIn:(NSString *)text base:(NSURL *)base {
    BOOL afterStreamInfo = NO;
    for (NSString *rawLine in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *line = [rawLine stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if ([line hasPrefix:@"#EXT-X-STREAM-INF"]) {
            afterStreamInfo = YES;
        } else if (afterStreamInfo && line.length > 0 && ![line hasPrefix:@"#"]) {
            return [NSURL URLWithString:line relativeToURL:base].absoluteURL;
        }
    }
    return nil;
}

static uint32_t BrowserReadUInt32(const uint8_t *bytes) {
    return ((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16) | ((uint32_t)bytes[2] << 8) | bytes[3];
}

/// Earliest PES presentation timestamp among the first packets of an MPEG-TS segment.
+ (long long)firstTimestampInTransportStream:(NSData *)data {
    const uint8_t *bytes = data.bytes;
    long long earliest = -1;
    NSUInteger found = 0;
    for (NSUInteger offset = 0; offset + 188 <= data.length && found < 8; offset += 188) {
        const uint8_t *packet = bytes + offset;
        if (packet[0] != 0x47 || !(packet[1] & 0x40)) {
            continue;
        }
        NSUInteger payload = 4;
        uint8_t adaptation = (packet[3] >> 4) & 0x3;
        if (adaptation == 2) {
            continue;
        }
        if (adaptation == 3) {
            payload += 1 + packet[4];
        }
        if (payload + 14 > 188) {
            continue;
        }
        const uint8_t *pes = packet + payload;
        if (pes[0] != 0 || pes[1] != 0 || pes[2] != 1 || !(pes[7] & 0x80)) {
            continue;
        }
        const uint8_t *pts = pes + 9;
        long long value = ((long long)((pts[0] >> 1) & 0x07) << 30) | ((long long)pts[1] << 22) |
                          ((long long)(pts[2] >> 1) << 15) | ((long long)pts[3] << 7) | (pts[4] >> 1);
        earliest = earliest < 0 ? value : MIN(earliest, value);
        found += 1;
    }
    return earliest;
}

/// Payload of the first box of `type` found anywhere in `data` (no full parse needed here).
+ (const uint8_t *)boxPayload:(const char *)type inData:(NSData *)data length:(NSUInteger *)lengthOut {
    NSData *needle = [NSData dataWithBytes:type length:4];
    NSRange range = [data rangeOfData:needle options:0 range:NSMakeRange(0, data.length)];
    if (range.location == NSNotFound || range.location < 4) {
        return NULL;
    }
    const uint8_t *start = (const uint8_t *)data.bytes + range.location - 4;
    uint32_t size = BrowserReadUInt32(start);
    NSUInteger available = data.length - (range.location - 4);
    if (size < 8 || size > available) {
        size = (uint32_t)MIN(available, 64);
    }
    *lengthOut = size - 8;
    return start + 8;
}

/// fMP4: first track's tfdt base decode time scaled to 90 kHz, using the init segment's timescale.
+ (long long)firstTimestampInFragment:(NSData *)fragment initSegment:(NSData *)initSegment {
    NSUInteger length = 0;
    const uint8_t *mdhd = [self boxPayload:"mdhd" inData:initSegment length:&length];
    if (mdhd == NULL || length < 24) {
        return -1;
    }
    uint32_t timescale = mdhd[0] == 1 ? BrowserReadUInt32(mdhd + 20) : BrowserReadUInt32(mdhd + 12);
    const uint8_t *tfdt = [self boxPayload:"tfdt" inData:fragment length:&length];
    if (tfdt == NULL || timescale == 0 || length < 8) {
        return -1;
    }
    unsigned long long decodeTime = tfdt[0] == 1 && length >= 12
        ? ((unsigned long long)BrowserReadUInt32(tfdt + 4) << 32) | BrowserReadUInt32(tfdt + 8)
        : BrowserReadUInt32(tfdt + 4);
    return (long long)((double)decodeTime * 90000.0 / timescale);
}

- (long long)streamStartTicks {
    [self.lock lock];
    NSNumber *known = self.startTicks;
    NSURL *probeURL = self.probeURL;
    [self.lock unlock];
    if (known != nil) {
        return known.longLongValue;
    }
    long long ticks = -1;
    NSURL *playlistURL = nil;
    NSData *playlistData = probeURL != nil ? [self fetchURL:probeURL status:NULL finalURL:&playlistURL] : nil;
    NSString *playlist = playlistData.length > 0 ? [[NSString alloc] initWithData:playlistData encoding:NSUTF8StringEncoding] : nil;
    NSURL *segmentURL = nil;
    NSURL *initURL = nil;
    for (NSString *rawLine in [playlist componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *line = [rawLine stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if ([line hasPrefix:@"#EXT-X-MAP:"]) {
            NSRange uri = [line rangeOfString:@"URI=\""];
            if (uri.location != NSNotFound) {
                NSString *rest = [line substringFromIndex:NSMaxRange(uri)];
                NSString *value = [rest componentsSeparatedByString:@"\""].firstObject;
                initURL = [NSURL URLWithString:value relativeToURL:playlistURL ?: probeURL].absoluteURL;
            }
        } else if (line.length > 0 && ![line hasPrefix:@"#"]) {
            segmentURL = [NSURL URLWithString:line relativeToURL:playlistURL ?: probeURL].absoluteURL;
            break;
        }
    }
    if (segmentURL != nil) {
        NSData *segment = [self fetchURL:segmentURL maximumLength:192 * 1024 status:NULL finalURL:NULL];
        if (segment.length >= 188 && ((const uint8_t *)segment.bytes)[0] == 0x47) {
            ticks = [[self class] firstTimestampInTransportStream:segment];
        } else if (segment.length > 0 && initURL != nil) {
            NSData *initSegment = [self fetchURL:initURL maximumLength:64 * 1024 status:NULL finalURL:NULL];
            ticks = [[self class] firstTimestampInFragment:segment initSegment:initSegment];
        }
    }
#if DEBUG
    NSLog(@"[Subtitles] Stream starts at %.3f s (%lld ticks)", ticks / 90000.0, ticks);
#endif
    [self.lock lock];
    self.startTicks = @(MAX(ticks, 0));
    [self.lock unlock];
    return MAX(ticks, 0);
}

/// Adds the timestamp map, unless the file already has one or the stream starts at zero.
- (NSString *)timedWebVTT:(NSString *)vtt {
    if ([vtt rangeOfString:@"X-TIMESTAMP-MAP"].location != NSNotFound) {
        return vtt;
    }
    long long ticks = [self streamStartTicks];
    if (ticks <= 0) {
        return vtt;
    }
    NSRange header = [vtt rangeOfString:@"\n"];
    if (header.location == NSNotFound) {
        return vtt;
    }
    return [NSString stringWithFormat:@"%@\nX-TIMESTAMP-MAP=MPEGTS:%lld,LOCAL:00:00:00.000%@",
            [vtt substringToIndex:header.location], ticks, [vtt substringFromIndex:header.location]];
}

#pragma mark Local server

/// A minimal HTTP/1.1 server on 127.0.0.1: AVFoundation loads subtitle segments only from
/// real http(s) addresses, never from a custom URL scheme.
- (uint16_t)startServer {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        return 0;
    }
    int yes = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));
    struct sockaddr_in address = {0};
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = 0;
    socklen_t length = sizeof(address);
    if (bind(fd, (struct sockaddr *)&address, sizeof(address)) != 0 || listen(fd, 16) != 0 ||
        getsockname(fd, (struct sockaddr *)&address, &length) != 0) {
        close(fd);
        return 0;
    }
    self.listenSocket = fd;
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)fd, 0, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0));
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(source, ^{
        int client = accept(fd, NULL, NULL);
        if (client < 0) {
            return;
        }
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            [weakSelf serveClient:client];
        });
    });
    dispatch_source_set_cancel_handler(source, ^{
        close(fd);
    });
    self.acceptSource = source;
    dispatch_resume(source);
    return ntohs(address.sin_port);
}

- (void)stopServer {
    if (self.acceptSource != nil) {
        dispatch_source_cancel(self.acceptSource);
        self.acceptSource = nil;
    }
    self.listenSocket = -1;
}

- (void)serveClient:(int)client {
    int yes = 1;
    setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));
    struct timeval timeout = { .tv_sec = 10, .tv_usec = 0 };
    setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));

    NSMutableData *request = [NSMutableData data];
    char buffer[4096];
    while (request.length < 32768) {
        ssize_t count = recv(client, buffer, sizeof(buffer), 0);
        if (count <= 0) {
            break;
        }
        [request appendBytes:buffer length:(NSUInteger)count];
        if ([request rangeOfData:[@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding] options:0 range:NSMakeRange(0, request.length)].location != NSNotFound) {
            break;
        }
    }
    NSString *head = [[NSString alloc] initWithData:request encoding:NSASCIIStringEncoding] ?: @"";
    NSArray<NSString *> *parts = [[head componentsSeparatedByString:@"\r\n"].firstObject componentsSeparatedByString:@" "];
    NSString *method = parts.count > 1 ? parts[0] : @"";
    NSString *path = parts.count > 1 ? [parts[1] componentsSeparatedByString:@"?"].firstObject : @"";

    NSString *contentType = @"text/plain";
    NSInteger status = 405;
    NSData *body = nil;
    if ([method isEqualToString:@"GET"] || [method isEqualToString:@"HEAD"]) {
        body = [self responseForPath:path contentType:&contentType status:&status];
    }
#if DEBUG
    NSLog(@"[Subtitles] %@ %@ -> %ld (%lu bytes)", method, path.lastPathComponent, (long)status, (unsigned long)body.length);
#endif
    NSString *reason = status == 200 ? @"OK" : [NSHTTPURLResponse localizedStringForStatusCode:status];
    NSString *header = [NSString stringWithFormat:@"HTTP/1.1 %ld %@\r\nContent-Type: %@\r\nContent-Length: %lu\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n",
                        (long)status, reason, contentType, (unsigned long)body.length];
    NSMutableData *response = [[header dataUsingEncoding:NSASCIIStringEncoding] mutableCopy];
    if (body != nil && ![method isEqualToString:@"HEAD"]) {
        [response appendData:body];
    }
    const uint8_t *bytes = response.bytes;
    NSUInteger sent = 0;
    while (sent < response.length) {
        ssize_t count = send(client, bytes + sent, response.length - sent, 0);
        if (count <= 0) {
            break;
        }
        sent += (NSUInteger)count;
    }
    close(client);
}

@end
