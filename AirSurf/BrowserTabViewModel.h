#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// What the app remembers about one tab, independent of its web view.
@interface BrowserTabViewModel : NSObject

/// Stable across launches; names the tab's web view and its thumbnail file.
@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *URLString;
/// WebKit's back/forward state, saved with the session.
@property (nonatomic, copy, nullable) NSData *interactionState;
/// The tab is showing the built-in start page instead of its web view.
@property (nonatomic) BOOL showsStartPage;
/// Thumbnail for the tab overview. Also written to Caches, so restored tabs have one before they are opened.
@property (nonatomic, strong, nullable) UIImage *snapshotImage;

- (instancetype)initWithSessionRepresentation:(NSDictionary *)sessionRepresentation;
/// A property-list dictionary for the saved session.
- (NSDictionary *)sessionRepresentation;
- (void)removeStoredSnapshot;

@end

NS_ASSUME_NONNULL_END
