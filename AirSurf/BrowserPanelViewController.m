#import "BrowserPanelViewController.h"

#import "BrowserTheme.h"

static CGFloat const kPanelWidth = 680.0;
static CGFloat const kPanelMargin = 40.0;
static CGFloat const kPanelCornerRadius = 40.0;
static CGFloat const kPanelRowHeight = 78.0;
static CGFloat const kPanelRowHeightWithSubtitle = 104.0;
static NSString * const kPanelCellIdentifier = @"BrowserPanelCell";
static NSString * const kPanelHeaderIdentifier = @"BrowserPanelHeader";

#pragma mark - Model

@implementation BrowserPanelItem

- (instancetype)init {
    self = [super init];
    if (self) {
        _title = @"";
        _enabled = YES;
    }
    return self;
}

+ (instancetype)itemWithTitle:(NSString *)title symbolName:(NSString *)symbolName handler:(void (^)(void))handler {
    BrowserPanelItem *item = [BrowserPanelItem new];
    item.title = title ?: @"";
    item.symbolName = symbolName;
    item.handler = handler;
    return item;
}

+ (instancetype)toggleWithTitle:(NSString *)title symbolName:(NSString *)symbolName isOn:(BOOL)isOn handler:(void (^)(void))handler {
    BrowserPanelItem *item = [self itemWithTitle:title symbolName:symbolName handler:handler];
    item.value = isOn ? @"On" : @"Off";
    item.keepsPanelOpen = YES;
    return item;
}

+ (instancetype)linkWithTitle:(NSString *)title symbolName:(NSString *)symbolName value:(NSString *)value page:(BrowserPanelPage *(^)(void))pageProvider {
    BrowserPanelItem *item = [self itemWithTitle:title symbolName:symbolName handler:nil];
    item.value = value;
    item.pageProvider = pageProvider;
    return item;
}

@end

@implementation BrowserPanelSection

+ (instancetype)sectionWithTitle:(NSString *)title items:(NSArray<BrowserPanelItem *> *)items {
    return [self sectionWithTitle:title footer:nil items:items];
}

+ (instancetype)sectionWithTitle:(NSString *)title footer:(NSString *)footer items:(NSArray<BrowserPanelItem *> *)items {
    BrowserPanelSection *section = [BrowserPanelSection new];
    section.title = title;
    section.footer = footer;
    section.items = items ?: @[];
    return section;
}

@end

@implementation BrowserPanelPage

+ (instancetype)pageWithTitle:(NSString *)title sections:(NSArray<BrowserPanelSection *> *(^)(void))sectionsProvider {
    BrowserPanelPage *page = [BrowserPanelPage new];
    page.title = title ?: @"";
    page.sectionsProvider = sectionsProvider;
    return page;
}

@end

#pragma mark - Cell

@interface BrowserPanelCell : UITableViewCell

@property (nonatomic) UIView *plateView;
@property (nonatomic) UIImageView *symbolView;
@property (nonatomic) UILabel *titleLabel;
@property (nonatomic) UILabel *subtitleLabel;
@property (nonatomic) UILabel *valueLabel;
@property (nonatomic) UIImageView *accessoryImageView;
@property (nonatomic) BrowserPanelItem *item;

@end

@implementation BrowserPanelCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.focusStyle = UITableViewCellFocusStyleCustom;
        self.clipsToBounds = NO;
        self.contentView.clipsToBounds = NO;

        _plateView = [[UIView alloc] initWithFrame:CGRectZero];
        _plateView.backgroundColor = UIColor.whiteColor;
        _plateView.alpha = 0.0;
        _plateView.layer.cornerRadius = 20.0;
        _plateView.layer.cornerCurve = kCACornerCurveContinuous;
        _plateView.layer.shadowColor = UIColor.blackColor.CGColor;
        _plateView.layer.shadowOpacity = 0.35;
        _plateView.layer.shadowRadius = 18.0;
        _plateView.layer.shadowOffset = CGSizeMake(0.0, 10.0);
        [self.contentView addSubview:_plateView];

        _symbolView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _symbolView.contentMode = UIViewContentModeCenter;
        [self.contentView addSubview:_symbolView];

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.font = [UIFont systemFontOfSize:30.0 weight:UIFontWeightMedium];
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:_titleLabel];

        _subtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _subtitleLabel.font = [UIFont systemFontOfSize:23.0 weight:UIFontWeightRegular];
        _subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:_subtitleLabel];

        _valueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _valueLabel.font = [UIFont systemFontOfSize:27.0 weight:UIFontWeightRegular];
        _valueLabel.textAlignment = NSTextAlignmentRight;
        [self.contentView addSubview:_valueLabel];

        _accessoryImageView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _accessoryImageView.contentMode = UIViewContentModeCenter;
        [self.contentView addSubview:_accessoryImageView];
    }
    return self;
}

- (void)configureWithItem:(BrowserPanelItem *)item {
    self.item = item;
    self.titleLabel.text = item.title;
    self.subtitleLabel.text = item.subtitle;
    self.subtitleLabel.hidden = item.subtitle.length == 0;
    self.valueLabel.text = item.value;
    self.symbolView.image = item.symbolName.length > 0 ? [BrowserTheme symbolNamed:item.symbolName pointSize:27.0 weight:UIImageSymbolWeightMedium] : nil;
    NSString *accessorySymbol = nil;
    if (item.checked) {
        accessorySymbol = @"checkmark";
    } else if (item.pageProvider != nil) {
        accessorySymbol = @"chevron.forward";
    }
    self.accessoryImageView.image = accessorySymbol != nil ? [BrowserTheme symbolNamed:accessorySymbol pointSize:21.0 weight:UIImageSymbolWeightSemibold] : nil;
    [self applyAppearance];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.contentView.bounds;
    self.plateView.frame = CGRectInset(bounds, 0.0, 3.0);

    CGFloat x = 22.0;
    if (self.symbolView.image != nil) {
        self.symbolView.frame = CGRectMake(x, 0.0, 44.0, CGRectGetHeight(bounds));
        x += 44.0 + 18.0;
    } else {
        self.symbolView.frame = CGRectZero;
    }

    CGFloat right = CGRectGetWidth(bounds) - 24.0;
    if (self.accessoryImageView.image != nil) {
        self.accessoryImageView.frame = CGRectMake(right - 26.0, 0.0, 26.0, CGRectGetHeight(bounds));
        right -= 26.0 + 12.0;
    } else {
        self.accessoryImageView.frame = CGRectZero;
    }
    CGFloat valueWidth = 0.0;
    if (self.valueLabel.text.length > 0) {
        valueWidth = MIN(ceil([self.valueLabel sizeThatFits:CGSizeMake(260.0, 40.0)].width), 260.0);
        self.valueLabel.frame = CGRectMake(right - valueWidth, 0.0, valueWidth, CGRectGetHeight(bounds));
        right -= valueWidth + 16.0;
    } else {
        self.valueLabel.frame = CGRectZero;
    }

    CGFloat textWidth = MAX(40.0, right - x);
    if (self.subtitleLabel.hidden) {
        self.titleLabel.frame = CGRectMake(x, 0.0, textWidth, CGRectGetHeight(bounds));
    } else {
        CGFloat midY = CGRectGetMidY(bounds);
        self.titleLabel.frame = CGRectMake(x, midY - 37.0, textWidth, 38.0);
        self.subtitleLabel.frame = CGRectMake(x, midY + 3.0, textWidth, 30.0);
    }
}

- (void)applyAppearance {
    BOOL focused = self.focused;
    BOOL enabled = self.item.enabled;
    UIColor *primary = focused ? [UIColor colorWithWhite:0.05 alpha:1.0] : [BrowserTheme primaryTextColor];
    UIColor *secondary = focused ? [UIColor colorWithWhite:0.05 alpha:0.6] : [BrowserTheme secondaryTextColor];
    if (self.item.destructive) {
        primary = focused ? [UIColor colorWithRed:0.85 green:0.1 blue:0.1 alpha:1.0] : [UIColor colorWithRed:1.0 green:0.42 blue:0.4 alpha:1.0];
    }
    self.titleLabel.textColor = primary;
    self.symbolView.tintColor = self.item.destructive ? primary : (focused ? [UIColor colorWithWhite:0.05 alpha:0.85] : [BrowserTheme primaryTextColor]);
    self.subtitleLabel.textColor = secondary;
    self.valueLabel.textColor = secondary;
    self.accessoryImageView.tintColor = self.item.checked ? (focused ? [UIColor colorWithWhite:0.05 alpha:1.0] : [BrowserTheme accentColor]) : secondary;
    self.plateView.alpha = focused ? 1.0 : 0.0;
    self.contentView.alpha = enabled ? 1.0 : 0.38;
    self.contentView.transform = focused ? CGAffineTransformMakeScale(1.03, 1.03) : CGAffineTransformIdentity;
}

- (BOOL)canBecomeFocused {
    return self.item.enabled;
}

- (void)didUpdateFocusInContext:(UIFocusUpdateContext *)context withAnimationCoordinator:(UIFocusAnimationCoordinator *)coordinator {
    [super didUpdateFocusInContext:context withAnimationCoordinator:coordinator];
    [coordinator addCoordinatedAnimations:^{
        [self applyAppearance];
    } completion:nil];
}

@end

#pragma mark - Panel

@interface BrowserPanelViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic) NSMutableArray<BrowserPanelPage *> *pageStack;
@property (nonatomic) NSMutableArray<NSIndexPath *> *focusStack;
@property (nonatomic, copy) NSArray<BrowserPanelSection *> *sections;
@property (nonatomic) UIView *dimView;
@property (nonatomic) UIVisualEffectView *panelView;
@property (nonatomic) UILabel *titleLabel;
@property (nonatomic) UIImageView *backChevronView;
@property (nonatomic) UILabel *footerLabel;
@property (nonatomic) UILabel *emptyLabel;
@property (nonatomic) UITableView *tableView;
@property (nonatomic) NSIndexPath *preferredIndexPath;
@property (nonatomic) BOOL didAnimateIn;
@property (nonatomic) BOOL dismissing;
@property (nonatomic) BOOL handlingMenuPress;

@end

@implementation BrowserPanelViewController

- (instancetype)initWithRootPage:(BrowserPanelPage *)rootPage {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _pageStack = [NSMutableArray arrayWithObject:rootPage];
        _focusStack = [NSMutableArray array];
        _sections = @[];
        self.modalPresentationStyle = UIModalPresentationOverFullScreen;
        self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    }
    return self;
}

- (BrowserPanelPage *)currentPage {
    return self.pageStack.lastObject;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;

    self.dimView = [[UIView alloc] initWithFrame:self.view.bounds];
    self.dimView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.dimView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.4];
    self.dimView.alpha = 0.0;
    [self.view addSubview:self.dimView];

    self.panelView = [[UIVisualEffectView alloc] initWithEffect:[BrowserTheme panelEffect]];
    self.panelView.clipsToBounds = YES;
    self.panelView.layer.cornerRadius = kPanelCornerRadius;
    self.panelView.layer.cornerCurve = kCACornerCurveContinuous;
    if ([BrowserTheme usesLightweightMaterials]) {
        self.panelView.layer.borderWidth = 1.0;
        self.panelView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.14].CGColor;
    }
    [self.view addSubview:self.panelView];

    self.backChevronView = [[UIImageView alloc] initWithImage:[BrowserTheme symbolNamed:@"chevron.backward" pointSize:26.0 weight:UIImageSymbolWeightSemibold]];
    self.backChevronView.tintColor = [BrowserTheme secondaryTextColor];
    self.backChevronView.contentMode = UIViewContentModeCenter;
    [self.panelView.contentView addSubview:self.backChevronView];

    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.titleLabel.font = [UIFont systemFontOfSize:42.0 weight:UIFontWeightBold];
    self.titleLabel.textColor = [BrowserTheme primaryTextColor];
    self.titleLabel.adjustsFontSizeToFitWidth = YES;
    self.titleLabel.minimumScaleFactor = 0.7;
    [self.panelView.contentView addSubview:self.titleLabel];

    self.footerLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.footerLabel.font = [UIFont systemFontOfSize:21.0 weight:UIFontWeightRegular];
    self.footerLabel.textColor = [BrowserTheme secondaryTextColor];
    self.footerLabel.textAlignment = NSTextAlignmentCenter;
    self.footerLabel.text = self.footerText;
    [self.panelView.contentView addSubview:self.footerLabel];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.clipsToBounds = YES;
    self.tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    self.tableView.insetsContentViewsToSafeArea = NO;
    self.tableView.insetsLayoutMarginsFromSafeArea = NO;
    self.tableView.preservesSuperviewLayoutMargins = NO;
    self.tableView.layoutMargins = UIEdgeInsetsZero;
    self.tableView.cellLayoutMarginsFollowReadableWidth = NO;
    self.tableView.sectionHeaderTopPadding = 0.0;
    self.tableView.remembersLastFocusedIndexPath = NO;
    self.tableView.contentInset = UIEdgeInsetsMake(8.0, 0.0, 28.0, 0.0);
    [self.tableView registerClass:[BrowserPanelCell class] forCellReuseIdentifier:kPanelCellIdentifier];
    [self.panelView.contentView addSubview:self.tableView];

    self.emptyLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.emptyLabel.font = [UIFont systemFontOfSize:27.0 weight:UIFontWeightRegular];
    self.emptyLabel.textColor = [BrowserTheme secondaryTextColor];
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.numberOfLines = 0;
    [self.panelView.contentView addSubview:self.emptyLabel];

    UILongPressGestureRecognizer *holdRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleHold:)];
    holdRecognizer.allowedPressTypes = @[@(UIPressTypeSelect)];
    holdRecognizer.minimumPressDuration = 0.55;
    [self.tableView addGestureRecognizer:holdRecognizer];

    [self layoutPanel];
    [self loadSectionsForCurrentPage];
    self.panelView.transform = [self offscreenTransform];
}

- (void)setFooterText:(NSString *)footerText {
    _footerText = [footerText copy];
    self.footerLabel.text = footerText;
}

- (CGAffineTransform)offscreenTransform {
    return CGAffineTransformMakeTranslation(kPanelWidth + kPanelMargin + 20.0, 0.0);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutPanel];
}

- (void)layoutPanel {
    CGRect bounds = self.view.bounds;
    CGAffineTransform transform = self.panelView.transform;
    self.panelView.transform = CGAffineTransformIdentity;
    self.panelView.frame = CGRectMake(CGRectGetWidth(bounds) - kPanelWidth - kPanelMargin,
                                      kPanelMargin,
                                      kPanelWidth,
                                      CGRectGetHeight(bounds) - kPanelMargin * 2.0);
    self.panelView.transform = transform;

    CGFloat width = kPanelWidth;
    CGFloat height = CGRectGetHeight(self.panelView.bounds);
    BOOL nested = self.pageStack.count > 1;
    CGFloat titleX = nested ? 76.0 : 44.0;
    self.backChevronView.frame = CGRectMake(34.0, 40.0, 32.0, 52.0);
    self.backChevronView.alpha = nested ? 1.0 : 0.0;
    self.titleLabel.frame = CGRectMake(titleX, 40.0, width - titleX - 40.0, 52.0);

    CGFloat footerHeight = self.footerLabel.text.length > 0 ? 54.0 : 16.0;
    self.footerLabel.frame = CGRectMake(24.0, height - footerHeight, width - 48.0, footerHeight - 14.0);
    CGRect tableFrame = CGRectMake(22.0, 108.0, width - 44.0, height - 108.0 - footerHeight);
    self.tableView.bounds = CGRectMake(self.tableView.bounds.origin.x, self.tableView.bounds.origin.y, CGRectGetWidth(tableFrame), CGRectGetHeight(tableFrame));
    self.tableView.center = CGPointMake(CGRectGetMidX(tableFrame), CGRectGetMidY(tableFrame));
    self.emptyLabel.frame = CGRectInset(tableFrame, 30.0, 60.0);
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.didAnimateIn) {
        return;
    }
    self.didAnimateIn = YES;
    [BrowserTheme animate:^{
        self.dimView.alpha = 1.0;
        self.panelView.transform = CGAffineTransformIdentity;
    }];
}

#pragma mark Pages

- (void)loadSectionsForCurrentPage {
    BrowserPanelPage *page = [self currentPage];
    NSArray<BrowserPanelSection *> *sections = page.sectionsProvider != nil ? page.sectionsProvider() : @[];
    NSMutableArray<BrowserPanelSection *> *nonEmptySections = [NSMutableArray array];
    for (BrowserPanelSection *section in sections) {
        if (section.items.count > 0) {
            [nonEmptySections addObject:section];
        }
    }
    self.sections = nonEmptySections;
    self.titleLabel.text = page.title;
    self.emptyLabel.text = page.emptyMessage;
    self.emptyLabel.hidden = nonEmptySections.count > 0;
}

- (BOOL)sectionsMatchShapeOf:(NSArray<BrowserPanelSection *> *)other {
    if (other.count != self.sections.count) {
        return NO;
    }
    for (NSUInteger index = 0; index < other.count; index += 1) {
        if (other[index].items.count != self.sections[index].items.count) {
            return NO;
        }
    }
    return YES;
}

- (void)reloadCurrentPage {
    if (!self.isViewLoaded) {
        return;
    }
    NSArray<BrowserPanelSection *> *previousSections = self.sections;
    [self loadSectionsForCurrentPage];
    if ([self sectionsMatchShapeOf:previousSections]) {
        // Same rows, new values: update in place so focus does not move.
        for (NSIndexPath *indexPath in self.tableView.indexPathsForVisibleRows) {
            BrowserPanelCell *cell = (BrowserPanelCell *)[self.tableView cellForRowAtIndexPath:indexPath];
            [cell configureWithItem:self.sections[(NSUInteger)indexPath.section].items[(NSUInteger)indexPath.row]];
        }
        return;
    }
    NSIndexPath *focused = [self focusedIndexPath];
    [self.tableView reloadData];
    self.preferredIndexPath = [self clampedIndexPath:focused];
    [self setNeedsFocusUpdate];
    [self updateFocusIfNeeded];
}

- (NSIndexPath *)clampedIndexPath:(NSIndexPath *)indexPath {
    if (self.sections.count == 0) {
        return nil;
    }
    NSInteger section = MIN(MAX(indexPath != nil ? indexPath.section : 0, 0), (NSInteger)self.sections.count - 1);
    NSInteger rowCount = (NSInteger)self.sections[(NSUInteger)section].items.count;
    NSInteger row = MIN(MAX(indexPath != nil ? indexPath.row : 0, 0), rowCount - 1);
    return [NSIndexPath indexPathForRow:row inSection:section];
}

- (NSIndexPath *)focusedIndexPath {
    UIView *focusedView = (UIView *)[UIFocusSystem focusSystemForEnvironment:self].focusedItem;
    if (![focusedView isKindOfClass:[UITableViewCell class]]) {
        return nil;
    }
    return [self.tableView indexPathForCell:(UITableViewCell *)focusedView];
}

- (void)transitionToCurrentPageMovingForward:(BOOL)forward restoringIndexPath:(NSIndexPath *)indexPath {
    CGFloat travel = forward ? 40.0 : -40.0;
    [UIView animateWithDuration:0.12 animations:^{
        self.tableView.alpha = 0.0;
        self.titleLabel.alpha = 0.0;
        self.tableView.transform = CGAffineTransformMakeTranslation(-travel, 0.0);
    } completion:^(__unused BOOL finished) {
        // Frames are only valid on an untransformed view; laying out while the list is still
        // shifted sideways left it too wide.
        self.tableView.transform = CGAffineTransformIdentity;
        [self loadSectionsForCurrentPage];
        [self layoutPanel];
        [self.tableView reloadData];
        [self.tableView setContentOffset:CGPointMake(0.0, -self.tableView.contentInset.top) animated:NO];
        self.preferredIndexPath = [self clampedIndexPath:indexPath];
        if (self.preferredIndexPath != nil) {
            [self.tableView scrollToRowAtIndexPath:self.preferredIndexPath atScrollPosition:UITableViewScrollPositionNone animated:NO];
        }
        [self setNeedsFocusUpdate];
        [self updateFocusIfNeeded];
        self.tableView.transform = CGAffineTransformMakeTranslation(travel, 0.0);
        [BrowserTheme animateQuick:^{
            self.tableView.alpha = 1.0;
            self.titleLabel.alpha = 1.0;
            self.tableView.transform = CGAffineTransformIdentity;
        }];
    }];
}

- (void)pushPage:(BrowserPanelPage *)page {
    if (page == nil) {
        return;
    }
    [self.focusStack addObject:[self focusedIndexPath] ?: [NSIndexPath indexPathForRow:0 inSection:0]];
    [self.pageStack addObject:page];
    [self transitionToCurrentPageMovingForward:YES restoringIndexPath:nil];
}

- (void)popPage {
    if (self.pageStack.count <= 1) {
        [self dismissPanelWithCompletion:nil];
        return;
    }
    [self.pageStack removeLastObject];
    NSIndexPath *indexPath = self.focusStack.lastObject;
    [self.focusStack removeLastObject];
    [self transitionToCurrentPageMovingForward:NO restoringIndexPath:indexPath];
}

- (void)dismissPanelWithCompletion:(void (^)(void))completion {
    if (self.dismissing) {
        return;
    }
    self.dismissing = YES;
    // Out the way it came in.
    [BrowserTheme animate:^{
        self.dimView.alpha = 0.0;
        self.panelView.transform = [self offscreenTransform];
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self dismissViewControllerAnimated:NO completion:completion];
    });
}

#pragma mark Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return (NSInteger)self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.sections[(NSUInteger)section].items.count;
}

- (BrowserPanelItem *)itemAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath == nil || indexPath.section >= (NSInteger)self.sections.count) {
        return nil;
    }
    NSArray<BrowserPanelItem *> *items = self.sections[(NSUInteger)indexPath.section].items;
    return indexPath.row < (NSInteger)items.count ? items[(NSUInteger)indexPath.row] : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    BrowserPanelCell *cell = [tableView dequeueReusableCellWithIdentifier:kPanelCellIdentifier forIndexPath:indexPath];
    [cell configureWithItem:[self itemAtIndexPath:indexPath]];
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return [self itemAtIndexPath:indexPath].subtitle.length > 0 ? kPanelRowHeightWithSubtitle : kPanelRowHeight;
}

- (UILabel *)supplementaryLabelWithText:(NSString *)text header:(BOOL)header {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.numberOfLines = 0;
    if (header) {
        label.attributedText = [[NSAttributedString alloc] initWithString:text.uppercaseString
                                                               attributes:@{ NSKernAttributeName: @1.2,
                                                                             NSFontAttributeName: [UIFont systemFontOfSize:21.0 weight:UIFontWeightSemibold],
                                                                             NSForegroundColorAttributeName: [BrowserTheme secondaryTextColor] }];
    } else {
        label.font = [UIFont systemFontOfSize:21.0 weight:UIFontWeightRegular];
        label.textColor = [BrowserTheme secondaryTextColor];
        label.text = text;
    }
    return label;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSString *title = self.sections[(NSUInteger)section].title;
    if (title.length == 0) {
        return [UIView new];
    }
    UIView *container = [UIView new];
    UILabel *label = [self supplementaryLabelWithText:title header:YES];
    label.frame = CGRectMake(22.0, 18.0, CGRectGetWidth(tableView.bounds) - 44.0, 30.0);
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [container addSubview:label];
    return container;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return self.sections[(NSUInteger)section].title.length > 0 ? 54.0 : (section == 0 ? 0.01 : 18.0);
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    NSString *footer = self.sections[(NSUInteger)section].footer;
    if (footer.length == 0) {
        return [UIView new];
    }
    UIView *container = [UIView new];
    UILabel *label = [self supplementaryLabelWithText:footer header:NO];
    CGFloat width = CGRectGetWidth(tableView.bounds) - 44.0;
    CGFloat height = ceil([label sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)].height);
    label.frame = CGRectMake(22.0, 8.0, width, height);
    [container addSubview:label];
    return container;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    NSString *footer = self.sections[(NSUInteger)section].footer;
    if (footer.length == 0) {
        return 0.01;
    }
    UILabel *label = [self supplementaryLabelWithText:footer header:NO];
    return ceil([label sizeThatFits:CGSizeMake(CGRectGetWidth(tableView.bounds) - 44.0, CGFLOAT_MAX)].height) + 18.0;
}

- (BOOL)tableView:(UITableView *)tableView canFocusRowAtIndexPath:(NSIndexPath *)indexPath {
    return [self itemAtIndexPath:indexPath].enabled;
}

- (NSIndexPath *)indexPathForPreferredFocusedViewInTableView:(UITableView *)tableView {
    return self.preferredIndexPath;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    BrowserPanelItem *item = [self itemAtIndexPath:indexPath];
    if (item == nil || !item.enabled || self.dismissing) {
        return;
    }
    if (item.pageProvider != nil) {
        [self pushPage:item.pageProvider()];
        return;
    }
    void (^handler)(void) = item.handler;
    if (item.keepsPanelOpen) {
        if (handler != nil) {
            handler();
        }
        [self reloadCurrentPage];
        return;
    }
    [self dismissPanelWithCompletion:handler];
}

- (void)handleHold:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateBegan) {
        return;
    }
    BrowserPanelItem *item = [self itemAtIndexPath:[self focusedIndexPath]];
    if (item.secondaryItemsProvider == nil) {
        return;
    }
    NSArray<BrowserPanelItem *> *secondaryItems = item.secondaryItemsProvider();
    if (secondaryItems.count == 0) {
        return;
    }
    [self pushPage:[BrowserPanelPage pageWithTitle:item.title sections:^NSArray<BrowserPanelSection *> *{
        return @[[BrowserPanelSection sectionWithTitle:nil items:secondaryItems]];
    }]];
}

#pragma mark Focus and presses

- (NSArray<id<UIFocusEnvironment>> *)preferredFocusEnvironments {
    return @[self.tableView];
}

- (BOOL)pressesContainMenuOrPlayPause:(NSSet<UIPress *> *)presses {
    for (UIPress *press in presses) {
        if (press.type == UIPressTypeMenu || press.type == UIPressTypePlayPause) {
            return YES;
        }
    }
    return NO;
}

- (void)pressesBegan:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    if ([self pressesContainMenuOrPlayPause:presses]) {
        // Swallowed here so the system does not treat Menu as "leave the app".
        self.handlingMenuPress = YES;
        return;
    }
    [super pressesBegan:presses withEvent:event];
}

- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    if ([self pressesContainMenuOrPlayPause:presses]) {
        BOOL wasHandling = self.handlingMenuPress;
        self.handlingMenuPress = NO;
        if (!wasHandling) {
            // The press began before the panel was on screen (it is what opened the panel).
            return;
        }
        BOOL isMenu = NO;
        for (UIPress *press in presses) {
            isMenu = isMenu || press.type == UIPressTypeMenu;
        }
        if (isMenu) {
            [self popPage];
        } else {
            [self dismissPanelWithCompletion:nil];
        }
        return;
    }
    [super pressesEnded:presses withEvent:event];
}

- (void)pressesCancelled:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    if ([self pressesContainMenuOrPlayPause:presses]) {
        self.handlingMenuPress = NO;
        return;
    }
    [super pressesCancelled:presses withEvent:event];
}

@end
