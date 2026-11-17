#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class BrowserCursorView;

NS_ASSUME_NONNULL_BEGIN

@protocol BrowserRemoteInputControllerHost <NSObject>
/// A web page is on screen with nothing over it, so the remote drives the cursor.
- (BOOL)inputControllerPointerIsActive;
- (nullable UIScrollView *)inputControllerScrollView;
- (void)inputControllerCursorDidMoveToPoint:(CGPoint)point;
- (void)inputControllerDidClickAtPoint:(CGPoint)point;
- (void)inputControllerDidHoldAtPoint:(CGPoint)point;
/// The page's own scroll view cannot move any further; scroll whatever is under the point.
- (void)inputControllerScrollInnerContentAtPoint:(CGPoint)point delta:(CGPoint)delta;
/// Whether Menu has something to do here (go back, close something). If not, tvOS gets it.
- (BOOL)inputControllerCanHandleMenuPress;
- (void)inputControllerHandleMenuPress;
- (void)inputControllerOpenMenu;
- (void)inputControllerScrollModeDidChange:(BOOL)scrollModeEnabled;
- (void)inputControllerDidFinishScrolling;
@end

/// Turns Siri Remote input into browsing.
///
///   Swipe            move the cursor; pushing against a screen edge scrolls the page
///   Click            click (acts immediately)
///   Hold click       actions for what is under the cursor
///   Play/Pause       switch between cursor mode and scroll mode
///   Hold Play/Pause  open the menu
///   Menu / Back      back, or leave the app from the start
///   Up / Down        scroll by most of a screen
@interface BrowserRemoteInputController : NSObject

@property (nonatomic, readonly) BrowserCursorView *cursorView;
/// Cursor hot spot in root view coordinates.
@property (nonatomic, readonly) CGPoint cursorPoint;
@property (nonatomic, getter=isScrollModeEnabled) BOOL scrollModeEnabled;
@property (nonatomic) CGFloat speedMultiplier;

- (instancetype)initWithHost:(id<BrowserRemoteInputControllerHost>)host
                    rootView:(UIView *)rootView NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Shows or hides the cursor to match the host's state.
- (void)refreshPointerState;
- (void)setCursorIsOverInteractiveContent:(BOOL)interactive;
- (void)moveCursorToPoint:(CGPoint)point;
- (void)stopScrolling;

/// Each returns YES when the event was consumed and must not reach `super`.
- (BOOL)handlePressesBegan:(NSSet<UIPress *> *)presses;
- (BOOL)handlePressesEnded:(NSSet<UIPress *> *)presses;
- (BOOL)handlePressesCancelled:(NSSet<UIPress *> *)presses;
- (BOOL)handleTouchesBegan:(NSSet<UITouch *> *)touches;
- (BOOL)handleTouchesMoved:(NSSet<UITouch *> *)touches;
- (BOOL)handleTouchesEnded:(NSSet<UITouch *> *)touches;

/// Select presses that never reached the view controller are replayed through here.
- (void)handleGlobalSelectPressEnded;

@end

NS_ASSUME_NONNULL_END
