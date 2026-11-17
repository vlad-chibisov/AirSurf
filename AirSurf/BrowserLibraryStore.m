#import "BrowserLibraryStore.h"

NSNotificationName const BrowserLibraryDidChangeNotification = @"BrowserLibraryDidChangeNotification";

// Entries are stored as [URL, title] pairs, the format the original app used, so existing
// favourites and history carry over.
static NSString * const kFavoritesDefaultsKey = @"FAVORITES";
static NSString * const kHistoryDefaultsKey = @"HISTORY";
static NSString * const kResumeDefaultsKey = @"VideoResumePositions";
static NSUInteger const kMaximumHistoryCount = 150;
static NSUInteger const kMaximumResumeCount = 60;

@interface BrowserLibraryEntry ()

@property (nonatomic, copy, readwrite) NSString *URLString;
@property (nonatomic, copy, readwrite) NSString *title;

@end

@implementation BrowserLibraryEntry

+ (instancetype)entryWithURLString:(NSString *)URLString title:(NSString *)title {
    BrowserLibraryEntry *entry = [BrowserLibraryEntry new];
    entry.URLString = URLString ?: @"";
    entry.title = title ?: @"";
    return entry;
}

- (NSString *)displayHost {
    NSString *host = [NSURL URLWithString:self.URLString].host ?: self.URLString;
    if ([host hasPrefix:@"www."]) {
        host = [host substringFromIndex:4];
    }
    return host;
}

- (NSString *)displayTitle {
    NSString *trimmed = [self.title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return trimmed.length > 0 ? trimmed : self.displayHost;
}

@end

@implementation BrowserLibraryStore

+ (instancetype)sharedStore {
    static BrowserLibraryStore *store;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        store = [BrowserLibraryStore new];
    });
    return store;
}

- (NSUserDefaults *)defaults {
    return [NSUserDefaults standardUserDefaults];
}

- (NSArray<BrowserLibraryEntry *> *)entriesForKey:(NSString *)key {
    NSMutableArray<BrowserLibraryEntry *> *entries = [NSMutableArray array];
    for (id stored in [[self defaults] arrayForKey:key] ?: @[]) {
        if (![stored isKindOfClass:[NSArray class]] || [stored count] == 0 || ![stored[0] isKindOfClass:[NSString class]]) {
            continue;
        }
        NSString *URLString = stored[0];
        if (URLString.length == 0) {
            continue;
        }
        NSString *title = ([stored count] > 1 && [stored[1] isKindOfClass:[NSString class]]) ? stored[1] : @"";
        [entries addObject:[BrowserLibraryEntry entryWithURLString:URLString title:title]];
    }
    return entries;
}

- (void)saveEntries:(NSArray<BrowserLibraryEntry *> *)entries forKey:(NSString *)key notify:(BOOL)notify {
    NSMutableArray *stored = [NSMutableArray arrayWithCapacity:entries.count];
    for (BrowserLibraryEntry *entry in entries) {
        [stored addObject:@[entry.URLString, entry.title ?: @""]];
    }
    [[self defaults] setObject:stored forKey:key];
    if (notify) {
        [[NSNotificationCenter defaultCenter] postNotificationName:BrowserLibraryDidChangeNotification object:self];
    }
}

- (NSArray<BrowserLibraryEntry *> *)favorites {
    return [self entriesForKey:kFavoritesDefaultsKey];
}

- (NSArray<BrowserLibraryEntry *> *)history {
    return [self entriesForKey:kHistoryDefaultsKey];
}

- (NSArray<BrowserLibraryEntry *> *)recentSitesWithLimit:(NSUInteger)limit {
    NSMutableSet<NSString *> *seenHosts = [NSMutableSet set];
    for (BrowserLibraryEntry *favorite in self.favorites) {
        [seenHosts addObject:favorite.displayHost];
    }
    NSMutableArray<BrowserLibraryEntry *> *recent = [NSMutableArray array];
    for (BrowserLibraryEntry *entry in self.history) {
        NSString *host = entry.displayHost;
        if (host.length == 0 || [seenHosts containsObject:host]) {
            continue;
        }
        [seenHosts addObject:host];
        [recent addObject:entry];
        if (recent.count >= limit) {
            break;
        }
    }
    return recent;
}

- (BOOL)isFavoriteURLString:(NSString *)URLString {
    if (URLString.length == 0) {
        return NO;
    }
    for (BrowserLibraryEntry *entry in self.favorites) {
        if ([entry.URLString isEqualToString:URLString]) {
            return YES;
        }
    }
    return NO;
}

- (void)addFavoriteWithURLString:(NSString *)URLString title:(NSString *)title {
    if (URLString.length == 0 || [self isFavoriteURLString:URLString]) {
        return;
    }
    NSMutableArray<BrowserLibraryEntry *> *favorites = [self.favorites mutableCopy];
    [favorites addObject:[BrowserLibraryEntry entryWithURLString:URLString title:title]];
    [self saveEntries:favorites forKey:kFavoritesDefaultsKey notify:YES];
}

- (void)removeFavoriteWithURLString:(NSString *)URLString {
    NSMutableArray<BrowserLibraryEntry *> *favorites = [NSMutableArray array];
    for (BrowserLibraryEntry *entry in self.favorites) {
        if (![entry.URLString isEqualToString:URLString]) {
            [favorites addObject:entry];
        }
    }
    [self saveEntries:favorites forKey:kFavoritesDefaultsKey notify:YES];
}

- (void)renameFavoriteWithURLString:(NSString *)URLString title:(NSString *)title {
    NSMutableArray<BrowserLibraryEntry *> *favorites = [NSMutableArray array];
    for (BrowserLibraryEntry *entry in self.favorites) {
        if ([entry.URLString isEqualToString:URLString]) {
            [favorites addObject:[BrowserLibraryEntry entryWithURLString:URLString title:title]];
        } else {
            [favorites addObject:entry];
        }
    }
    [self saveEntries:favorites forKey:kFavoritesDefaultsKey notify:YES];
}

- (void)recordVisitWithURLString:(NSString *)URLString title:(NSString *)title {
    NSURL *URL = [NSURL URLWithString:URLString ?: @""];
    NSString *scheme = URL.scheme.lowercaseString;
    if (URL == nil || !([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])) {
        return;
    }
    NSMutableArray<BrowserLibraryEntry *> *history = [NSMutableArray arrayWithObject:[BrowserLibraryEntry entryWithURLString:URLString title:title]];
    for (BrowserLibraryEntry *entry in self.history) {
        if (![entry.URLString isEqualToString:URLString]) {
            [history addObject:entry];
        }
    }
    while (history.count > kMaximumHistoryCount) {
        [history removeLastObject];
    }
    [self saveEntries:history forKey:kHistoryDefaultsKey notify:NO];
}

- (void)removeHistoryEntryWithURLString:(NSString *)URLString {
    NSMutableArray<BrowserLibraryEntry *> *history = [NSMutableArray array];
    for (BrowserLibraryEntry *entry in self.history) {
        if (![entry.URLString isEqualToString:URLString]) {
            [history addObject:entry];
        }
    }
    [self saveEntries:history forKey:kHistoryDefaultsKey notify:YES];
}

- (void)clearHistory {
    [[self defaults] removeObjectForKey:kHistoryDefaultsKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:BrowserLibraryDidChangeNotification object:self];
}

- (NSTimeInterval)resumePositionForKey:(NSString *)key duration:(NSTimeInterval)duration {
    NSDictionary *positions = [[self defaults] dictionaryForKey:kResumeDefaultsKey];
    NSDictionary *entry = key.length > 0 ? positions[key] : nil;
    if (![entry isKindOfClass:[NSDictionary class]]) {
        return 0;
    }
    if (fabs([entry[@"duration"] doubleValue] - duration) > 3.0) {
        return 0;
    }
    return [entry[@"position"] doubleValue];
}

- (void)setResumePosition:(NSTimeInterval)position duration:(NSTimeInterval)duration forKey:(NSString *)key {
    if (key.length == 0) {
        return;
    }
    NSMutableDictionary *positions = [([[self defaults] dictionaryForKey:kResumeDefaultsKey] ?: @{}) mutableCopy];
    BOOL nearStart = position < 30.0;
    BOOL nearEnd = duration > 0 && position > duration - MAX(30.0, duration * 0.04);
    if (nearStart || nearEnd || !isfinite(position)) {
        [positions removeObjectForKey:key];
    } else {
        positions[key] = @{ @"position": @(position), @"duration": @(duration), @"saved": @([NSDate date].timeIntervalSince1970) };
    }
    if (positions.count > kMaximumResumeCount) {
        NSArray<NSString *> *oldestFirst = [positions keysSortedByValueUsingComparator:^NSComparisonResult(NSDictionary *first, NSDictionary *second) {
            return [first[@"saved"] compare:second[@"saved"]];
        }];
        NSUInteger excess = positions.count - kMaximumResumeCount;
        for (NSUInteger index = 0; index < excess; index += 1) {
            [positions removeObjectForKey:oldestFirst[index]];
        }
    }
    [[self defaults] setObject:positions forKey:kResumeDefaultsKey];
}

@end
