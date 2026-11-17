#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class BrowserTabOverviewController;
@class BrowserViewModel;

@protocol BrowserTabOverviewControllerDelegate <NSObject>
- (void)tabOverviewController:(BrowserTabOverviewController *)controller didSelectTabAtIndex:(NSInteger)tabIndex;
- (void)tabOverviewController:(BrowserTabOverviewController *)controller didCloseTabAtIndex:(NSInteger)tabIndex;
- (void)tabOverviewControllerDidRequestNewTab:(BrowserTabOverviewController *)controller;
@end

/// Full-screen grid of open tabs. Select opens a tab, Play/Pause closes the highlighted one.
@interface BrowserTabOverviewController : UIViewController

@property (nonatomic, weak, nullable) id<BrowserTabOverviewControllerDelegate> delegate;

- (instancetype)initWithViewModel:(BrowserViewModel *)viewModel NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

- (void)reloadTabs;
- (void)reloadTabAtIndex:(NSInteger)tabIndex;

@end

NS_ASSUME_NONNULL_END
