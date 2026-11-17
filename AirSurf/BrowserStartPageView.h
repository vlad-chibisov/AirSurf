#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class BrowserLibraryEntry;
@class BrowserStartPageView;

@protocol BrowserStartPageViewDelegate <NSObject>
- (void)startPageView:(BrowserStartPageView *)startPageView didSelectEntry:(BrowserLibraryEntry *)entry;
/// Select was held on a tile.
- (void)startPageView:(BrowserStartPageView *)startPageView didRequestActionsForEntry:(BrowserLibraryEntry *)entry isFavorite:(BOOL)isFavorite;
@end

/// What a new tab shows: favourites and recently visited sites as focusable tiles.
@interface BrowserStartPageView : UIView

@property (nonatomic, weak, nullable) id<BrowserStartPageViewDelegate> delegate;
/// Space reserved at the top for the toolbar.
@property (nonatomic) CGFloat topInset;

- (void)reloadContent;

@end

NS_ASSUME_NONNULL_END
