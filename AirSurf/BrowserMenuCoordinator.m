#import "BrowserMenuCoordinator.h"

#import "BrowserLibraryStore.h"
#import "BrowserPanelViewController.h"
#import "BrowserPreferencesStore.h"
#import "BrowserWebView.h"

@interface BrowserMenuCoordinator ()

@property (nonatomic, weak) id<BrowserMenuCoordinatorHost> host;
@property (nonatomic) BrowserPreferencesStore *preferencesStore;

@end

@implementation BrowserMenuCoordinator

- (instancetype)initWithHost:(id<BrowserMenuCoordinatorHost>)host preferencesStore:(BrowserPreferencesStore *)preferencesStore {
    self = [super init];
    if (self) {
        _host = host;
        _preferencesStore = preferencesStore;
    }
    return self;
}

- (NSString *)versionText {
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    NSString *version = info[@"CFBundleShortVersionString"] ?: @"";
    NSString *build = info[@"CFBundleVersion"] ?: @"";
    NSString *name = info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"] ?: @"";
    return [NSString stringWithFormat:@"%@ %@ (%@)", name, version, build];
}

- (void)presentPage:(BrowserPanelPage *)page {
    BrowserPanelViewController *panel = [[BrowserPanelViewController alloc] initWithRootPage:page];
    panel.footerText = [self versionText];
    [self.host browserPresentViewController:panel];
}

#pragma mark Menu

- (void)showMenu {
    [self presentPage:[self menuPage]];
}

- (BrowserPanelPage *)menuPage {
    __weak typeof(self) weakSelf = self;
    return [BrowserPanelPage pageWithTitle:@"AirSurf" sections:^NSArray<BrowserPanelSection *> *{
        typeof(self) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return @[];
        }
        return @[
            [strongSelf pageSection],
            [strongSelf browseSection],
            [BrowserPanelSection sectionWithTitle:nil items:@[
                [BrowserPanelItem linkWithTitle:@"Settings" symbolName:@"gearshape" value:nil page:^BrowserPanelPage *{
                    return [weakSelf settingsPage];
                }],
                [BrowserPanelItem linkWithTitle:@"Remote Guide" symbolName:@"appletvremote.gen4" value:nil page:^BrowserPanelPage *{
                    return [weakSelf usageGuidePage];
                }],
            ]],
        ];
    }];
}

- (BrowserPanelSection *)pageSection {
    __weak typeof(self) weakSelf = self;
    id<BrowserMenuCoordinatorHost> host = self.host;
    NSMutableArray<BrowserPanelItem *> *items = [NSMutableArray array];

    NSArray<BrowserMediaCandidate *> *videos = host.browserShowingStartPage ? @[] : [host browserPlayableVideos];
    if (videos.count > 0) {
        BrowserMediaCandidate *best = videos.firstObject;
        BrowserPanelItem *playItem = [BrowserPanelItem itemWithTitle:@"Play Video Full Screen" symbolName:@"play.rectangle.fill" handler:^{
            [weakSelf.host browserPlayVideo:best];
        }];
        playItem.subtitle = [NSString stringWithFormat:@"%@ · %@", best.displayName, best.URL.host ?: @""];
        [items addObject:playItem];
        if (videos.count > 1) {
            [items addObject:[BrowserPanelItem linkWithTitle:@"All Videos on This Page" symbolName:@"list.bullet.rectangle"
                                                       value:[NSString stringWithFormat:@"%lu", (unsigned long)videos.count]
                                                        page:^BrowserPanelPage *{
                return [weakSelf videosPageWithCandidates:videos];
            }]];
        }
    }

    [items addObject:[BrowserPanelItem itemWithTitle:@"Search or Enter Website" symbolName:@"magnifyingglass" handler:^{
        [weakSelf.host browserShowAddressEntry];
    }]];
    if (!host.browserShowingStartPage && host.browserWebView.request.URL != nil) {
        BOOL isFavorite = [host browserCurrentPageIsFavorite];
        [items addObject:[BrowserPanelItem itemWithTitle:isFavorite ? @"Remove from Favorites" : @"Add to Favorites"
                                              symbolName:isFavorite ? @"star.slash" : @"star"
                                                 handler:^{
            [weakSelf.host browserToggleFavoriteForCurrentPage];
        }]];
    }
    if (!host.browserShowingStartPage) {
        [items addObject:[BrowserPanelItem itemWithTitle:@"Start Page" symbolName:@"square.grid.2x2" handler:^{
            [weakSelf.host browserShowStartPage];
        }]];
    }
    return [BrowserPanelSection sectionWithTitle:nil items:items];
}

- (BrowserPanelSection *)browseSection {
    __weak typeof(self) weakSelf = self;
    BrowserLibraryStore *library = [BrowserLibraryStore sharedStore];
    return [BrowserPanelSection sectionWithTitle:@"Browse" items:@[
        [BrowserPanelItem linkWithTitle:@"Favorites" symbolName:@"star.fill"
                                  value:[NSString stringWithFormat:@"%lu", (unsigned long)library.favorites.count]
                                   page:^BrowserPanelPage *{
            return [weakSelf favoritesPage];
        }],
        [BrowserPanelItem linkWithTitle:@"History" symbolName:@"clock" value:nil page:^BrowserPanelPage *{
            return [weakSelf historyPage];
        }],
        [BrowserPanelItem itemWithTitle:@"Tabs" symbolName:@"square.on.square" handler:^{
            [weakSelf.host browserShowTabOverview];
        }],
        [BrowserPanelItem itemWithTitle:@"New Tab" symbolName:@"plus.square.on.square" handler:^{
            [weakSelf.host browserOpenNewTab];
        }],
    ]];
}

- (BrowserPanelPage *)videosPageWithCandidates:(NSArray<BrowserMediaCandidate *> *)candidates {
    __weak typeof(self) weakSelf = self;
    BrowserPanelPage *page = [BrowserPanelPage pageWithTitle:@"Videos" sections:^NSArray<BrowserPanelSection *> *{
        NSMutableArray<BrowserPanelItem *> *items = [NSMutableArray array];
        for (BrowserMediaCandidate *candidate in candidates) {
            BrowserPanelItem *item = [BrowserPanelItem itemWithTitle:candidate.displayName symbolName:@"play.fill" handler:^{
                [weakSelf.host browserPlayVideo:candidate];
            }];
            item.subtitle = candidate.URL.absoluteString;
            [items addObject:item];
        }
        return @[[BrowserPanelSection sectionWithTitle:nil
                                                footer:@"Streams this page has loaded, the most likely first. If the first one is an advert, try the next."
                                                 items:items]];
    }];
    return page;
}

#pragma mark Favorites and history

- (void)showFavorites {
    [self presentPage:[self favoritesPage]];
}

- (void)showHistory {
    [self presentPage:[self historyPage]];
}

- (NSArray<BrowserPanelItem *> *)secondaryItemsForURLString:(NSString *)URLString title:(NSString *)title isFavorite:(BOOL)isFavorite {
    __weak typeof(self) weakSelf = self;
    BrowserLibraryStore *library = [BrowserLibraryStore sharedStore];
    NSMutableArray<BrowserPanelItem *> *items = [NSMutableArray array];
    [items addObject:[BrowserPanelItem itemWithTitle:@"Open" symbolName:@"arrow.up.right" handler:^{
        [weakSelf.host browserLoadURLString:URLString];
    }]];
    [items addObject:[BrowserPanelItem itemWithTitle:@"Open in New Tab" symbolName:@"plus.square.on.square" handler:^{
        [weakSelf.host browserOpenURLStringInNewTab:URLString];
    }]];
    if (isFavorite) {
        [items addObject:[BrowserPanelItem itemWithTitle:@"Rename" symbolName:@"pencil" handler:^{
            [weakSelf presentRenameFavoriteWithURLString:URLString title:title];
        }]];
        BrowserPanelItem *remove = [BrowserPanelItem itemWithTitle:@"Remove from Favorites" symbolName:@"star.slash" handler:^{
            [library removeFavoriteWithURLString:URLString];
            [weakSelf.host browserShowStatus:@"Removed from Favorites" symbolName:@"star.slash"];
        }];
        remove.destructive = YES;
        [items addObject:remove];
    } else {
        if (![library isFavoriteURLString:URLString]) {
            [items addObject:[BrowserPanelItem itemWithTitle:@"Add to Favorites" symbolName:@"star" handler:^{
                [library addFavoriteWithURLString:URLString title:title];
                [weakSelf.host browserShowStatus:@"Added to Favorites" symbolName:@"star.fill"];
            }]];
        }
        BrowserPanelItem *remove = [BrowserPanelItem itemWithTitle:@"Remove from History" symbolName:@"trash" handler:^{
            [library removeHistoryEntryWithURLString:URLString];
        }];
        remove.destructive = YES;
        [items addObject:remove];
    }
    return items;
}

- (void)showActionsForURLString:(NSString *)URLString title:(NSString *)title isFavorite:(BOOL)isFavorite {
    NSArray<BrowserPanelItem *> *items = [self secondaryItemsForURLString:URLString title:title isFavorite:isFavorite];
    NSString *displayTitle = [BrowserLibraryEntry entryWithURLString:URLString title:title].displayTitle;
    [self presentPage:[BrowserPanelPage pageWithTitle:displayTitle sections:^NSArray<BrowserPanelSection *> *{
        return @[[BrowserPanelSection sectionWithTitle:nil footer:URLString items:items]];
    }]];
}

- (BrowserPanelItem *)itemForEntry:(BrowserLibraryEntry *)entry isFavorite:(BOOL)isFavorite {
    __weak typeof(self) weakSelf = self;
    BrowserPanelItem *item = [BrowserPanelItem itemWithTitle:entry.displayTitle symbolName:nil handler:^{
        [weakSelf.host browserLoadURLString:entry.URLString];
    }];
    item.subtitle = entry.URLString;
    item.secondaryItemsProvider = ^NSArray<BrowserPanelItem *> *{
        return [weakSelf secondaryItemsForURLString:entry.URLString title:entry.title isFavorite:isFavorite];
    };
    return item;
}

- (BrowserPanelPage *)favoritesPage {
    __weak typeof(self) weakSelf = self;
    BrowserPanelPage *page = [BrowserPanelPage pageWithTitle:@"Favorites" sections:^NSArray<BrowserPanelSection *> *{
        NSMutableArray<BrowserPanelItem *> *items = [NSMutableArray array];
        for (BrowserLibraryEntry *entry in [BrowserLibraryStore sharedStore].favorites) {
            [items addObject:[weakSelf itemForEntry:entry isFavorite:YES]];
        }
        return @[[BrowserPanelSection sectionWithTitle:nil footer:items.count > 0 ? @"Hold Select on a favorite to rename or remove it." : nil items:items]];
    }];
    page.emptyMessage = @"No favorites yet.\nOpen a page and choose the star in the toolbar.";
    return page;
}

- (BrowserPanelPage *)historyPage {
    __weak typeof(self) weakSelf = self;
    BrowserPanelPage *page = [BrowserPanelPage pageWithTitle:@"History" sections:^NSArray<BrowserPanelSection *> *{
        NSArray<BrowserLibraryEntry *> *history = [BrowserLibraryStore sharedStore].history;
        if (history.count == 0) {
            return @[];
        }
        NSMutableArray<BrowserPanelItem *> *items = [NSMutableArray array];
        for (BrowserLibraryEntry *entry in history) {
            [items addObject:[weakSelf itemForEntry:entry isFavorite:NO]];
        }
        BrowserPanelItem *clear = [BrowserPanelItem itemWithTitle:@"Clear History" symbolName:@"trash" handler:^{
            [weakSelf confirmClearHistory];
        }];
        clear.destructive = YES;
        return @[
            [BrowserPanelSection sectionWithTitle:nil items:items],
            [BrowserPanelSection sectionWithTitle:nil items:@[clear]],
        ];
    }];
    page.emptyMessage = @"Pages you visit appear here.";
    return page;
}

- (void)confirmClearHistory {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Clear History?"
                                                                   message:@"Recently visited sites on the start page are cleared too. Favorites stay."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Clear History" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        [[BrowserLibraryStore sharedStore] clearHistory];
        [weakSelf.host browserShowStatus:@"History cleared" symbolName:@"trash"];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self.host browserPresentViewController:alert];
}

- (void)presentRenameFavoriteWithURLString:(NSString *)URLString title:(NSString *)title {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Rename Favorite" message:URLString preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = title;
        textField.placeholder = @"Name";
        textField.returnKeyType = UIReturnKeyDone;
    }];
    __weak typeof(alert) weakAlert = alert;
    UIAlertAction *save = [UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSString *newTitle = [weakAlert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        [[BrowserLibraryStore sharedStore] renameFavoriteWithURLString:URLString title:newTitle ?: @""];
    }];
    [alert addAction:save];
    alert.preferredAction = save;
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self.host browserPresentViewController:alert];
}

#pragma mark Settings

- (void)showSettings {
    [self presentPage:[self settingsPage]];
}

- (void)showMenuThenSettings {
    BrowserPanelViewController *panel = [[BrowserPanelViewController alloc] initWithRootPage:[self menuPage]];
    panel.footerText = [self versionText];
    [self.host browserPresentViewController:panel];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [panel pushPage:[self settingsPage]];
    });
}

- (BrowserPanelPage *)settingsPage {
    __weak typeof(self) weakSelf = self;
    return [BrowserPanelPage pageWithTitle:@"Settings" sections:^NSArray<BrowserPanelSection *> *{
        typeof(self) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return @[];
        }
        return @[
            [strongSelf blockingSection],
            [strongSelf videoSection],
            [strongSelf browsingSection],
            [strongSelf dataSection],
        ];
    }];
}

- (BrowserPanelSection *)blockingSection {
    __weak typeof(self) weakSelf = self;
    BrowserWebEnvironment *environment = [BrowserWebEnvironment sharedEnvironment];
    BrowserPreferencesStore *preferences = self.preferencesStore;

    BrowserPanelItem *adBlocking = [BrowserPanelItem toggleWithTitle:@"Block Ads and Trackers" symbolName:@"hand.raised.fill"
                                                                isOn:environment.contentBlockingEnabled && environment.contentBlockingAvailable
                                                             handler:^{
        environment.contentBlockingEnabled = !environment.contentBlockingEnabled;
        [weakSelf.host browserPreferencesDidChange:BrowserPreferenceChangeContentBlocking];
    }];
    adBlocking.enabled = environment.contentBlockingAvailable;

    NSString *footer = nil;
    if (!environment.contentBlockingAvailable) {
        footer = [NSString stringWithFormat:@"Ad blocking could not start (%@). Pop-up blocking still works.",
                  environment.contentBlockingFailureReason ?: @"unknown reason"];
    } else {
        NSUInteger blocked = self.host.browserWebView.blockedRequestCount;
        footer = [NSString stringWithFormat:@"%lu ad and tracker addresses are blocked%@. Pop-ups are windows a page opens without you choosing a link; most are ads.",
                  (unsigned long)environment.contentRuleCount,
                  blocked > 0 ? [NSString stringWithFormat:@"; %lu requests stopped on this page", (unsigned long)blocked] : @""];
    }

    BrowserPanelItem *popups = [BrowserPanelItem toggleWithTitle:@"Block Pop-ups" symbolName:@"macwindow.badge.plus" isOn:preferences.blockPopups handler:^{
        preferences.blockPopups = !preferences.blockPopups;
        [weakSelf.host browserPreferencesDidChange:BrowserPreferenceChangePopups];
    }];
    return [BrowserPanelSection sectionWithTitle:@"Blocking" footer:footer items:@[adBlocking, popups]];
}

- (BrowserPanelSection *)videoSection {
    __weak typeof(self) weakSelf = self;
    BrowserPreferencesStore *preferences = self.preferencesStore;
    BrowserPanelItem *nativePlayer = [BrowserPanelItem toggleWithTitle:@"Open Videos in tvOS Player" symbolName:@"play.tv"
                                                                  isOn:preferences.nativeVideoPlayerEnabled
                                                               handler:^{
        preferences.nativeVideoPlayerEnabled = !preferences.nativeVideoPlayerEnabled;
    }];
    (void)weakSelf;
    return [BrowserPanelSection sectionWithTitle:@"Video"
                                          footer:@"Choose the voice-over, episode and quality in the site’s player, then press its full-screen button: the video continues in the Apple TV player. Off: full screen stays inside the page."
                                           items:@[nativePlayer]];
}

- (BrowserPanelSection *)browsingSection {
    __weak typeof(self) weakSelf = self;
    BrowserPreferencesStore *preferences = self.preferencesStore;

    BrowserPanelItem *zoom = [BrowserPanelItem linkWithTitle:@"Page Zoom" symbolName:@"textformat.size"
                                                       value:[NSString stringWithFormat:@"%lu%%", (unsigned long)preferences.pageZoomPercent]
                                                        page:^BrowserPanelPage *{
        return [weakSelf choicePageWithTitle:@"Page Zoom"
                                      titles:@[@"75%", @"100%", @"125%", @"150%", @"175%", @"200%"]
                                    selected:^BOOL(NSUInteger index) {
            return preferences.pageZoomPercent == 75 + index * 25;
        } choose:^(NSUInteger index) {
            preferences.pageZoomPercent = 75 + index * 25;
            [weakSelf.host browserPreferencesDidChange:BrowserPreferenceChangePageZoom];
        } footer:@"How large pages are drawn. 125% suits most sites on a TV."];
    }];

    BrowserPanelItem *toolbar = [BrowserPanelItem toggleWithTitle:@"Always Show Toolbar" symbolName:@"menubar.rectangle"
                                                             isOn:preferences.topNavigationBarVisible
                                                          handler:^{
        preferences.topNavigationBarVisible = !preferences.topNavigationBarVisible;
        [weakSelf.host browserPreferencesDidChange:BrowserPreferenceChangeToolbar];
    }];
    toolbar.subtitle = @"Off: point at the top edge to show it";

    BrowserPanelItem *mode = [BrowserPanelItem linkWithTitle:@"Request Websites As" symbolName:@"desktopcomputer"
                                                       value:preferences.mobileModeEnabled ? @"Mobile" : @"Desktop"
                                                        page:^BrowserPanelPage *{
        return [weakSelf choicePageWithTitle:@"Request Websites As"
                                      titles:@[@"Desktop", @"Mobile"]
                                    selected:^BOOL(NSUInteger index) {
            return preferences.mobileModeEnabled == (index == 1);
        } choose:^(NSUInteger index) {
            BOOL mobile = (index == 1);
            if (preferences.mobileModeEnabled == mobile) {
                return;
            }
            preferences.mobileModeEnabled = mobile;
            [weakSelf.host browserPreferencesDidChange:BrowserPreferenceChangeUserAgent];
        } footer:@"Mobile versions of sites are simpler and often faster, but some video players only appear on the desktop version."];
    }];

    BrowserPanelItem *search = [BrowserPanelItem linkWithTitle:@"Search Engine" symbolName:@"magnifyingglass"
                                                         value:[BrowserPreferencesStore nameForSearchEngine:preferences.searchEngine]
                                                          page:^BrowserPanelPage *{
        NSArray<NSNumber *> *engines = @[@(BrowserSearchEngineGoogle), @(BrowserSearchEngineYandex), @(BrowserSearchEngineDuckDuckGo), @(BrowserSearchEngineBing)];
        NSMutableArray<NSString *> *titles = [NSMutableArray array];
        for (NSNumber *engine in engines) {
            [titles addObject:[BrowserPreferencesStore nameForSearchEngine:engine.integerValue]];
        }
        return [weakSelf choicePageWithTitle:@"Search Engine" titles:titles selected:^BOOL(NSUInteger index) {
            return preferences.searchEngine == engines[index].integerValue;
        } choose:^(NSUInteger index) {
            preferences.searchEngine = engines[index].integerValue;
        } footer:nil];
    }];

    BrowserPanelItem *cursor = [BrowserPanelItem linkWithTitle:@"Pointer Speed" symbolName:@"cursorarrow.motionlines"
                                                         value:[BrowserPreferencesStore nameForCursorSpeed:preferences.cursorSpeed]
                                                          page:^BrowserPanelPage *{
        return [weakSelf choicePageWithTitle:@"Pointer Speed" titles:@[@"Slow", @"Normal", @"Fast"] selected:^BOOL(NSUInteger index) {
            return preferences.cursorSpeed == (BrowserCursorSpeed)index;
        } choose:^(NSUInteger index) {
            preferences.cursorSpeed = (BrowserCursorSpeed)index;
            [weakSelf.host browserPreferencesDidChange:BrowserPreferenceChangeCursorSpeed];
        } footer:nil];
    }];

    NSString *homeValue = preferences.homePageURLString.length > 0 ? ([NSURL URLWithString:preferences.homePageURLString].host ?: @"Custom") : @"Start Page";
    BrowserPanelItem *home = [BrowserPanelItem linkWithTitle:@"New Tabs Open" symbolName:@"house" value:homeValue page:^BrowserPanelPage *{
        return [weakSelf homePageChoicePage];
    }];

    return [BrowserPanelSection sectionWithTitle:@"Browsing" items:@[zoom, toolbar, mode, search, cursor, home]];
}

- (BrowserPanelPage *)homePageChoicePage {
    __weak typeof(self) weakSelf = self;
    BrowserPreferencesStore *preferences = self.preferencesStore;
    return [BrowserPanelPage pageWithTitle:@"New Tabs Open" sections:^NSArray<BrowserPanelSection *> *{
        typeof(self) strongSelf = weakSelf;
        NSMutableArray<BrowserPanelItem *> *items = [NSMutableArray array];
        BrowserPanelItem *startPage = [BrowserPanelItem itemWithTitle:@"Start Page" symbolName:@"square.grid.2x2" handler:^{
            preferences.homePageURLString = @"";
        }];
        startPage.checked = preferences.homePageURLString.length == 0;
        startPage.keepsPanelOpen = YES;
        [items addObject:startPage];

        if (preferences.homePageURLString.length > 0) {
            BrowserPanelItem *current = [BrowserPanelItem itemWithTitle:[NSURL URLWithString:preferences.homePageURLString].host ?: preferences.homePageURLString
                                                             symbolName:@"globe" handler:nil];
            current.subtitle = preferences.homePageURLString;
            current.checked = YES;
            current.keepsPanelOpen = YES;
            [items addObject:current];
        }
        NSString *pageURLString = strongSelf.host.browserShowingStartPage ? nil : strongSelf.host.browserWebView.request.URL.absoluteString;
        if (pageURLString.length > 0 && ![pageURLString isEqualToString:preferences.homePageURLString]) {
            BrowserPanelItem *useCurrent = [BrowserPanelItem itemWithTitle:@"This Page" symbolName:@"plus" handler:^{
                preferences.homePageURLString = pageURLString;
            }];
            useCurrent.subtitle = pageURLString;
            useCurrent.keepsPanelOpen = YES;
            [items addObject:useCurrent];
        }
        return @[[BrowserPanelSection sectionWithTitle:nil items:items]];
    }];
}

- (BrowserPanelSection *)dataSection {
    __weak typeof(self) weakSelf = self;
    BrowserPanelItem *cache = [BrowserPanelItem itemWithTitle:@"Clear Cache" symbolName:@"internaldrive" handler:^{
        [BrowserWebView clearCachedDataWithCompletion:^{
            [weakSelf.host browserShowStatus:@"Cache cleared" symbolName:@"checkmark.circle"];
        }];
    }];
    BrowserPanelItem *cookies = [BrowserPanelItem itemWithTitle:@"Clear Cookies and Site Data" symbolName:@"trash" handler:^{
        [weakSelf confirmClearCookies];
    }];
    cookies.destructive = YES;
    cookies.subtitle = @"Signs you out of websites";
    return [BrowserPanelSection sectionWithTitle:@"Data" items:@[cache, cookies]];
}

- (void)confirmClearCookies {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Clear Cookies and Site Data?"
                                                                   message:@"You will be signed out of websites. History and favorites stay."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Clear" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        [BrowserWebView resetWebsiteDataWithCompletion:^{
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"ApplicationCookie"];
            [weakSelf.host.browserWebView reload];
            [weakSelf.host browserShowStatus:@"Cookies and site data cleared" symbolName:@"checkmark.circle"];
        }];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self.host browserPresentViewController:alert];
}

- (BrowserPanelPage *)choicePageWithTitle:(NSString *)title
                                   titles:(NSArray<NSString *> *)titles
                                 selected:(BOOL (^)(NSUInteger index))isSelected
                                   choose:(void (^)(NSUInteger index))choose
                                   footer:(NSString *)footer {
    return [BrowserPanelPage pageWithTitle:title sections:^NSArray<BrowserPanelSection *> *{
        NSMutableArray<BrowserPanelItem *> *items = [NSMutableArray array];
        [titles enumerateObjectsUsingBlock:^(NSString *optionTitle, NSUInteger index, __unused BOOL *stop) {
            BrowserPanelItem *item = [BrowserPanelItem itemWithTitle:optionTitle symbolName:nil handler:^{
                choose(index);
            }];
            item.checked = isSelected(index);
            item.keepsPanelOpen = YES;
            [items addObject:item];
        }];
        return @[[BrowserPanelSection sectionWithTitle:nil footer:footer items:items]];
    }];
}

#pragma mark Guide

- (void)showUsageGuide {
    [self presentPage:[self usageGuidePage]];
}

- (BrowserPanelPage *)usageGuidePage {
    return [BrowserPanelPage pageWithTitle:@"Remote Guide" sections:^NSArray<BrowserPanelSection *> *{
        NSArray<NSArray<NSString *> *> *pageRows = @[
            @[@"hand.point.up.left", @"Swipe", @"Move the pointer. Push it past an edge to scroll."],
            @[@"button.programmable", @"Click", @"Click what is under the pointer"],
            @[@"hand.tap", @"Hold Click", @"Actions: open link in new tab, play video full screen"],
            @[@"playpause", @"Play/Pause", @"Switch to scroll mode, where swipes scroll the page"],
            @[@"ellipsis.circle", @"Hold Play/Pause", @"Open this menu"],
            @[@"arrow.up.arrow.down", @"Up / Down", @"Scroll a screen at a time"],
            @[@"chevron.backward", @"Back", @"Previous page, then the start page"],
        ];
        NSArray<NSArray<NSString *> *> *videoRows = @[
            @[@"play.rectangle", @"Click a video", @"Plays it in the page; pick voice-over and quality there"],
            @[@"arrow.up.left.and.arrow.down.right", @"Its full-screen button", @"Continues in the Apple TV player"],
            @[@"arrow.counterclockwise", @"Come back later", @"Videos resume where you stopped"],
        ];
        NSMutableArray<BrowserPanelSection *> *sections = [NSMutableArray array];
        for (NSArray<NSArray<NSString *> *> *rows in @[pageRows, videoRows]) {
            NSMutableArray<BrowserPanelItem *> *items = [NSMutableArray array];
            for (NSArray<NSString *> *row in rows) {
                BrowserPanelItem *item = [BrowserPanelItem itemWithTitle:row[1] symbolName:row[0] handler:nil];
                item.subtitle = row[2];
                item.keepsPanelOpen = YES;
                [items addObject:item];
            }
            [sections addObject:[BrowserPanelSection sectionWithTitle:(rows == pageRows ? @"On a Page" : @"Video") items:items]];
        }
        return sections;
    }];
}

@end
