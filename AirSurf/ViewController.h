#import <UIKit/UIKit.h>

/// The browser's root screen: the active tab's page or start page, the toolbar and the remote handling.
@interface ViewController : UIViewController

/// Saves open tabs and history; called when the app goes to the background.
- (void)persistState;

@end
