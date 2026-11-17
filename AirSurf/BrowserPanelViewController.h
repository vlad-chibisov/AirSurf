#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class BrowserPanelViewController;
@class BrowserPanelPage;

/// One row in a side panel.
@interface BrowserPanelItem : NSObject

@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy, nullable) NSString *subtitle;
/// Trailing text: the current setting ("On", "125%").
@property (nonatomic, copy, nullable) NSString *value;
@property (nonatomic, copy, nullable) NSString *symbolName;
@property (nonatomic) BOOL destructive;
@property (nonatomic) BOOL enabled;
@property (nonatomic) BOOL checked;
/// The panel stays up and refreshes after the handler runs (settings that toggle in place).
@property (nonatomic) BOOL keepsPanelOpen;
@property (nonatomic, copy, nullable) void (^handler)(void);
/// Selecting the row opens another page inside the panel.
@property (nonatomic, copy, nullable) BrowserPanelPage * (^pageProvider)(void);
/// Holding Select on the row opens a page with these actions.
@property (nonatomic, copy, nullable) NSArray<BrowserPanelItem *> * (^secondaryItemsProvider)(void);

+ (instancetype)itemWithTitle:(NSString *)title symbolName:(nullable NSString *)symbolName handler:(void (^ _Nullable)(void))handler;
+ (instancetype)toggleWithTitle:(NSString *)title symbolName:(nullable NSString *)symbolName isOn:(BOOL)isOn handler:(void (^)(void))handler;
+ (instancetype)linkWithTitle:(NSString *)title symbolName:(nullable NSString *)symbolName value:(nullable NSString *)value page:(BrowserPanelPage * (^)(void))pageProvider;

@end

@interface BrowserPanelSection : NSObject

@property (nonatomic, copy, nullable) NSString *title;
@property (nonatomic, copy, nullable) NSString *footer;
@property (nonatomic, copy) NSArray<BrowserPanelItem *> *items;

+ (instancetype)sectionWithTitle:(nullable NSString *)title items:(NSArray<BrowserPanelItem *> *)items;
+ (instancetype)sectionWithTitle:(nullable NSString *)title footer:(nullable NSString *)footer items:(NSArray<BrowserPanelItem *> *)items;

@end

/// A page of rows. Sections are produced by a block so the page can refresh itself
/// after a setting changes.
@interface BrowserPanelPage : NSObject

@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy, nullable) NSString *emptyMessage;
@property (nonatomic, copy) NSArray<BrowserPanelSection *> * (^sectionsProvider)(void);

+ (instancetype)pageWithTitle:(NSString *)title sections:(NSArray<BrowserPanelSection *> * (^)(void))sectionsProvider;

@end

/// Side panel that slides in from the trailing edge: the menu, favourites, history,
/// and context actions all use it.
@interface BrowserPanelViewController : UIViewController

- (instancetype)initWithRootPage:(BrowserPanelPage *)rootPage NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@property (nonatomic, copy, nullable) NSString *footerText;

- (void)pushPage:(BrowserPanelPage *)page;
- (void)popPage;
- (void)reloadCurrentPage;
- (void)dismissPanelWithCompletion:(void (^ _Nullable)(void))completion;

@end

NS_ASSUME_NONNULL_END
