#import "BrowserViewModel.h"

#import "BrowserTabViewModel.h"

@implementation BrowserViewModel {
    NSMutableArray<BrowserTabViewModel *> *_openTabs;
}

+ (NSUInteger)maximumTabCount {
    // An Apple TV 4K has 3 GB; half a dozen live pages fit with room to spare.
    return 6;
}

- (instancetype)init {
    if ((self = [super init])) {
        _openTabs = [NSMutableArray new];
        _activeTabIndex = NSNotFound;
    }
    return self;
}

- (NSArray<BrowserTabViewModel *> *)tabs {
    return _openTabs;
}

- (BOOL)isValidIndex:(NSInteger)index {
    return index >= 0 && index < (NSInteger)_openTabs.count;
}

- (BrowserTabViewModel *)activeTab {
    return [self isValidIndex:_activeTabIndex] ? _openTabs[(NSUInteger)_activeTabIndex] : nil;
}

- (BrowserTabViewModel *)addTab {
    if (_openTabs.count >= [BrowserViewModel maximumTabCount]) {
        return nil;
    }
    BrowserTabViewModel *tab = [BrowserTabViewModel new];
    [_openTabs addObject:tab];
    _activeTabIndex = (NSInteger)_openTabs.count - 1;
    return tab;
}

- (BrowserTabViewModel *)removeTabAtIndex:(NSInteger)tabIndex {
    if (![self isValidIndex:tabIndex]) {
        return nil;
    }
    BrowserTabViewModel *tab = _openTabs[(NSUInteger)tabIndex];
    [_openTabs removeObjectAtIndex:(NSUInteger)tabIndex];

    if (_openTabs.count == 0) {
        _activeTabIndex = NSNotFound;
    } else if (tabIndex < _activeTabIndex || _activeTabIndex >= (NSInteger)_openTabs.count) {
        // Tabs to the left of the front one shift it down; closing the last tab moves focus left.
        _activeTabIndex -= 1;
    }
    return tab;
}

- (void)restoreTabs:(NSArray<BrowserTabViewModel *> *)tabs activeTabIndex:(NSInteger)activeTabIndex {
    _openTabs = [tabs mutableCopy] ?: [NSMutableArray new];
    if (_openTabs.count == 0) {
        _activeTabIndex = NSNotFound;
    } else {
        _activeTabIndex = [self isValidIndex:activeTabIndex] ? activeTabIndex : 0;
    }
}

- (void)switchToTabAtIndex:(NSInteger)tabIndex {
    if ([self isValidIndex:tabIndex]) {
        _activeTabIndex = tabIndex;
    }
}

@end
