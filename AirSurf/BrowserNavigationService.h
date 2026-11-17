#import <Foundation/Foundation.h>

@class BrowserPreferencesStore;

NS_ASSUME_NONNULL_BEGIN

/// Turns addresses, typed text and search queries into requests carrying the chosen user agent.
@interface BrowserNavigationService : NSObject

- (instancetype)initWithPreferencesStore:(BrowserPreferencesStore *)preferencesStore NS_DESIGNATED_INITIALIZER;

/// nil when the home page is the built-in start page.
- (nullable NSURLRequest *)homePageRequest;
- (nullable NSURLRequest *)requestForURLString:(NSString *)URLString;
/// Whatever was typed into the address field: an address is opened, anything else is searched for.
- (nullable NSURLRequest *)requestForUserInput:(NSString *)input;
- (nullable NSURLRequest *)searchRequestForQuery:(NSString *)query;
/// Load failures that aren't worth telling the user about.
- (BOOL)shouldIgnoreLoadError:(NSError *)error;

@end

NS_ASSUME_NONNULL_END
