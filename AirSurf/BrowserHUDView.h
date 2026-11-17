#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Brief status message near the bottom of the screen ("Scroll mode", "Pop-up blocked").
@interface BrowserHUDView : UIView

- (void)showMessage:(NSString *)message symbolName:(nullable NSString *)symbolName;
/// Stays until `hide` or another message.
- (void)showPersistentMessage:(NSString *)message symbolName:(nullable NSString *)symbolName;
- (void)hide;

@end

NS_ASSUME_NONNULL_END
