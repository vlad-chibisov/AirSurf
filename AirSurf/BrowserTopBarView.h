#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, BrowserTopBarAction) {
    BrowserTopBarActionBack = 0,
    BrowserTopBarActionForward,
    BrowserTopBarActionReload,
    BrowserTopBarActionAddress,
    BrowserTopBarActionFavorite,
    BrowserTopBarActionTabs,
    BrowserTopBarActionMenu
};

@class BrowserTopBarView;

@protocol BrowserTopBarViewDelegate <NSObject>
- (void)browserTopBarView:(BrowserTopBarView *)topBarView didTriggerAction:(BrowserTopBarAction)action;
@end

/// Floating toolbar. It is operated two ways: by the on-screen cursor while a page is
/// showing (hover + activate), and by the focus engine while the start page is showing.
@interface BrowserTopBarView : UIView

/// Vertical space the toolbar occupies, including the gap below it.
+ (CGFloat)preferredHeight;

@property (nonatomic, weak, nullable) id<BrowserTopBarViewDelegate> delegate;

@property (nonatomic) BOOL canGoBack;
@property (nonatomic) BOOL canGoForward;
@property (nonatomic, getter=isLoading) BOOL loading;
@property (nonatomic, getter=isFavorite) BOOL favorite;
/// NO on the start page, where there is nothing to bookmark or reload.
@property (nonatomic) BOOL pageActionsEnabled;
@property (nonatomic) NSUInteger tabCount;
/// 0...1.
@property (nonatomic) double progress;
/// The buttons take part in the focus engine.
@property (nonatomic) BOOL focusEnabled;

- (void)setTitle:(nullable NSString *)title URLString:(nullable NSString *)URLString;

/// Cursor support. Points are in this view's coordinates.
- (BOOL)updateHoverAtPoint:(CGPoint)point;
- (BOOL)activateAtPoint:(CGPoint)point;
- (void)clearHover;

@property (nonatomic, readonly) UIView *addressFocusItem;

@end

NS_ASSUME_NONNULL_END
