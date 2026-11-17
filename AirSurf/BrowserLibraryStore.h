#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const BrowserLibraryDidChangeNotification;

@interface BrowserLibraryEntry : NSObject

@property (nonatomic, copy, readonly) NSString *URLString;
@property (nonatomic, copy, readonly) NSString *title;
/// Title if there is one, otherwise the host.
@property (nonatomic, readonly) NSString *displayTitle;
/// Host without a leading "www.".
@property (nonatomic, readonly) NSString *displayHost;

+ (instancetype)entryWithURLString:(NSString *)URLString title:(nullable NSString *)title;

@end

/// Favourites, history and video resume positions. Stored in NSUserDefaults because tvOS
/// gives apps no other storage that survives a cache purge.
@interface BrowserLibraryStore : NSObject

+ (instancetype)sharedStore;

@property (nonatomic, readonly) NSArray<BrowserLibraryEntry *> *favorites;
@property (nonatomic, readonly) NSArray<BrowserLibraryEntry *> *history;
/// Most recent history entries, one per site, without sites already in favourites.
- (NSArray<BrowserLibraryEntry *> *)recentSitesWithLimit:(NSUInteger)limit;

- (BOOL)isFavoriteURLString:(NSString *)URLString;
- (void)addFavoriteWithURLString:(NSString *)URLString title:(nullable NSString *)title;
- (void)removeFavoriteWithURLString:(NSString *)URLString;
- (void)renameFavoriteWithURLString:(NSString *)URLString title:(NSString *)title;

- (void)recordVisitWithURLString:(NSString *)URLString title:(nullable NSString *)title;
- (void)removeHistoryEntryWithURLString:(NSString *)URLString;
- (void)clearHistory;

/// A saved position is only returned for a video of the same length, so different episodes
/// watched on one page do not inherit each other's position.
- (NSTimeInterval)resumePositionForKey:(NSString *)key duration:(NSTimeInterval)duration;
- (void)setResumePosition:(NSTimeInterval)position duration:(NSTimeInterval)duration forKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
