#import "BrowserNavigationService.h"

#import "BrowserPreferencesStore.h"

@implementation BrowserNavigationService {
    BrowserPreferencesStore *_preferences;
}

- (instancetype)init {
    return [self initWithPreferencesStore:[BrowserPreferencesStore new]];
}

- (instancetype)initWithPreferencesStore:(BrowserPreferencesStore *)preferencesStore {
    if ((self = [super init])) {
        _preferences = preferencesStore;
    }
    return self;
}

- (NSURLRequest *)homePageRequest {
    return [self requestForURLString:_preferences.homePageURLString];
}

- (NSURLRequest *)requestForURLString:(NSString *)URLString {
    NSURL *URL = URLString.length > 0 ? [NSURL URLWithString:URLString] : nil;
    if (URL == nil) {
        return nil;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:URL];
    [request setValue:_preferences.userAgent forHTTPHeaderField:@"User-Agent"];
    return request;
}

- (BOOL)inputLooksLikeAddress:(NSString *)input {
    if ([input rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound) {
        return NO;
    }
    NSString *lower = input.lowercaseString;
    if ([lower hasPrefix:@"http://"] || [lower hasPrefix:@"https://"]) {
        return YES;
    }
    NSString *hostPart = [lower componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/?#"]].firstObject ?: @"";
    hostPart = [hostPart componentsSeparatedByString:@":"].firstObject ?: @"";
    if ([hostPart isEqualToString:@"localhost"]) {
        return YES;
    }
    // "something.tld" or an IP address.
    NSRange lastDot = [hostPart rangeOfString:@"." options:NSBackwardsSearch];
    if (lastDot.location == NSNotFound || lastDot.location == 0) {
        return NO;
    }
    NSString *suffix = [hostPart substringFromIndex:lastDot.location + 1];
    return suffix.length >= 1 && [suffix rangeOfCharacterFromSet:NSCharacterSet.alphanumericCharacterSet.invertedSet].location == NSNotFound;
}

- (NSURLRequest *)requestForUserInput:(NSString *)input {
    NSString *trimmed = [input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        return nil;
    }
    if ([self inputLooksLikeAddress:trimmed]) {
        NSString *lower = trimmed.lowercaseString;
        NSString *URLString = ([lower hasPrefix:@"http://"] || [lower hasPrefix:@"https://"]) ? trimmed : [@"https://" stringByAppendingString:trimmed];
        NSURLRequest *request = [self requestForURLString:URLString];
        if (request != nil) {
            return request;
        }
    }
    return [self searchRequestForQuery:trimmed];
}

- (NSURLRequest *)searchRequestForQuery:(NSString *)query {
    NSString *trimmed = [query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        return nil;
    }
    NSURLComponents *components = [NSURLComponents new];
    components.scheme = @"https";
    NSString *parameterName = @"q";
    switch (_preferences.searchEngine) {
        case BrowserSearchEngineYandex:
            components.host = @"yandex.ru";
            components.path = @"/search/";
            parameterName = @"text";
            break;
        case BrowserSearchEngineDuckDuckGo:
            components.host = @"duckduckgo.com";
            components.path = @"/";
            break;
        case BrowserSearchEngineBing:
            components.host = @"www.bing.com";
            components.path = @"/search";
            break;
        case BrowserSearchEngineGoogle:
            components.host = @"www.google.com";
            components.path = @"/search";
            break;
    }
    components.queryItems = @[[NSURLQueryItem queryItemWithName:parameterName value:trimmed]];
    return [self requestForURLString:components.URL.absoluteString];
}

- (BOOL)shouldIgnoreLoadError:(NSError *)error {
    if ([error.domain isEqualToString:NSURLErrorDomain]) {
        // A newer navigation replaced this one.
        return error.code == NSURLErrorCancelled;
    }
    // WebKit's "frame load interrupted" (102) and "plug-in handled load" (204): what a page
    // reports when its video was handed to the system player instead.
    return error.code == 102 || error.code == 204;
}

@end
