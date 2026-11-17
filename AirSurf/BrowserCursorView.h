#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, BrowserCursorStyle) {
    /// Plain pointer.
    BrowserCursorStyleDefault = 0,
    /// Over something clickable.
    BrowserCursorStyleLink,
    /// Scroll mode: swipes move the page instead of the pointer.
    BrowserCursorStyleScroll,
};

/// The on-screen pointer. Its hot spot is its centre.
@interface BrowserCursorView : UIView

@property (nonatomic) BrowserCursorStyle style;
@property (nonatomic, getter=isPressed) BOOL pressed;

@end

NS_ASSUME_NONNULL_END
