#import <Foundation/Foundation.h>

@class BrowserTabViewModel;

NS_ASSUME_NONNULL_BEGIN

/// The ordered list of open tabs and which one is in front.
@interface BrowserViewModel : NSObject

@property (nonatomic, readonly) NSArray<BrowserTabViewModel *> *tabs;
/// NSNotFound while there are no tabs.
@property (nonatomic, readonly) NSInteger activeTabIndex;

/// Every tab keeps its web view alive, so the count is capped to stay within an Apple TV's memory.
+ (NSUInteger)maximumTabCount;

- (nullable BrowserTabViewModel *)activeTab;
/// Appends a tab and brings it to the front; nil when the cap is reached.
- (nullable BrowserTabViewModel *)addTab;
- (nullable BrowserTabViewModel *)removeTabAtIndex:(NSInteger)tabIndex;
- (void)restoreTabs:(NSArray<BrowserTabViewModel *> *)tabs activeTabIndex:(NSInteger)activeTabIndex;
- (void)switchToTabAtIndex:(NSInteger)tabIndex;

@end

NS_ASSUME_NONNULL_END
