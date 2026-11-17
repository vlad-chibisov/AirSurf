#import <UIKit/UIKit.h>

// WebKit ships on tvOS but is not part of the public SDK. These protocols describe the parts
// of its Objective-C API that the browser calls, so those calls are type-checked. The real
// classes are looked up at runtime (see BrowserWebView.m); nothing here is linked.

NS_ASSUME_NONNULL_BEGIN

@protocol BrowserWKFrameInfo <NSObject>
@property (nonatomic, readonly, getter=isMainFrame) BOOL mainFrame;
@end

@protocol BrowserWKNavigationAction <NSObject>
@property (nonatomic, readonly, copy) NSURLRequest *request;
/// WKNavigationType: 0 = followed link, -1 = other (script, redirects).
@property (nonatomic, readonly) NSInteger navigationType;
@property (nonatomic, readonly, nullable) id<BrowserWKFrameInfo> targetFrame;
@end

@protocol BrowserWKHTTPCookieStore <NSObject>
- (void)getAllCookies:(void (^)(NSArray<NSHTTPCookie *> *cookies))completionHandler;
- (void)setCookie:(NSHTTPCookie *)cookie completionHandler:(nullable void (^)(void))completionHandler;
- (void)deleteCookie:(NSHTTPCookie *)cookie completionHandler:(nullable void (^)(void))completionHandler;
@end

@protocol BrowserWKWebsiteDataStore <NSObject>
+ (id<BrowserWKWebsiteDataStore>)defaultDataStore;
+ (NSSet<NSString *> *)allWebsiteDataTypes;
@property (nonatomic, readonly) id<BrowserWKHTTPCookieStore> httpCookieStore;
- (void)removeDataOfTypes:(NSSet<NSString *> *)dataTypes modifiedSince:(NSDate *)date completionHandler:(void (^)(void))completionHandler;
@end

@protocol BrowserWKWebView <NSObject>
@property (nonatomic, readonly, nullable) NSURL *URL;
@property (nonatomic, readonly, nullable, copy) NSString *title;
@property (nonatomic, readonly) BOOL canGoBack;
@property (nonatomic, readonly) BOOL canGoForward;
@property (nonatomic, readonly) double estimatedProgress;
@property (nonatomic, readonly) UIScrollView *scrollView;
@property (nonatomic, nullable, copy) NSString *customUserAgent;
@property (nonatomic, nullable, weak) id navigationDelegate;
@property (nonatomic, nullable, weak) id UIDelegate;
@property (nonatomic) BOOL allowsBackForwardNavigationGestures;
- (nullable id)loadRequest:(NSURLRequest *)request;
- (nullable id)reload;
- (nullable id)goBack;
- (nullable id)goForward;
- (void)stopLoading;
- (void)evaluateJavaScript:(NSString *)script completionHandler:(nullable void (^)(id _Nullable result, NSError * _Nullable error))completionHandler;
@end

NS_ASSUME_NONNULL_END
