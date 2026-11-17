#import "BrowserSessionStore.h"

#import "BrowserTabViewModel.h"
#import "BrowserViewModel.h"

static NSString * const kFallbackDefaultsKey = @"BrowserSession";

@implementation BrowserSessionStore

- (NSURL *)fileURL {
    NSURL *caches = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
    return [caches URLByAppendingPathComponent:@"Session.plist"];
}

- (NSDictionary *)sessionWithTabs:(NSArray<NSDictionary *> *)tabs frontTab:(NSInteger)frontTab {
    return @{ @"version": @2, @"activeTabIndex": @(frontTab), @"tabs": tabs };
}

- (nullable NSDictionary *)loadSession {
    NSData *file = [NSData dataWithContentsOfURL:self.fileURL];
    id session = file.length > 0 ? [NSPropertyListSerialization propertyListWithData:file options:NSPropertyListImmutable format:NULL error:NULL] : nil;
    if (![session isKindOfClass:[NSDictionary class]]) {
        session = [NSUserDefaults.standardUserDefaults objectForKey:kFallbackDefaultsKey];
    }
    return [session isKindOfClass:[NSDictionary class]] ? session : nil;
}

- (BOOL)restoreSessionIntoViewModel:(BrowserViewModel *)viewModel {
    NSDictionary *session = [self loadSession];
    id savedTabs = session[@"tabs"];
    if (![savedTabs isKindOfClass:[NSArray class]]) {
        return NO;
    }
    NSMutableArray<BrowserTabViewModel *> *tabs = [NSMutableArray new];
    for (id savedTab in savedTabs) {
        if (tabs.count == [BrowserViewModel maximumTabCount]) {
            break;
        }
        if ([savedTab isKindOfClass:[NSDictionary class]]) {
            [tabs addObject:[[BrowserTabViewModel alloc] initWithSessionRepresentation:savedTab]];
        }
    }
    if (tabs.count == 0) {
        return NO;
    }
    id frontTab = session[@"activeTabIndex"];
    [viewModel restoreTabs:tabs activeTabIndex:[frontTab isKindOfClass:[NSNumber class]] ? [frontTab integerValue] : 0];
    return YES;
}

- (void)saveSessionForViewModel:(BrowserViewModel *)viewModel {
    NSArray<NSDictionary *> *tabs = [viewModel.tabs valueForKey:NSStringFromSelector(@selector(sessionRepresentation))];
    NSInteger frontTab = viewModel.activeTabIndex == NSNotFound ? 0 : viewModel.activeTabIndex;

    NSData *file = [NSPropertyListSerialization dataWithPropertyList:[self sessionWithTabs:tabs frontTab:frontTab]
                                                              format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
    [file writeToURL:self.fileURL atomically:YES];

    NSMutableArray<NSDictionary *> *smallTabs = [NSMutableArray arrayWithCapacity:tabs.count];
    for (NSDictionary *tab in tabs) {
        NSMutableDictionary *small = [tab mutableCopy];
        [small removeObjectForKey:@"interactionState"];
        [smallTabs addObject:small];
    }
    [NSUserDefaults.standardUserDefaults setObject:[self sessionWithTabs:smallTabs frontTab:frontTab] forKey:kFallbackDefaultsKey];
}

@end
