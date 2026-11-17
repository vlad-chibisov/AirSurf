#import <Foundation/Foundation.h>

@class BrowserViewModel;

NS_ASSUME_NONNULL_BEGIN

/// Keeps the open tabs across launches.
///
/// tvOS caps an app's user defaults at roughly 500 KB, and WebKit's back/forward state can be
/// tens of kilobytes per tab. The full session is therefore written to a file in Caches, and
/// user defaults get a copy without the back/forward state, for when tvOS purges Caches.
@interface BrowserSessionStore : NSObject

/// Fills the tab list from the saved session. NO when there was nothing to restore.
- (BOOL)restoreSessionIntoViewModel:(BrowserViewModel *)viewModel;
- (void)saveSessionForViewModel:(BrowserViewModel *)viewModel;

@end

NS_ASSUME_NONNULL_END
