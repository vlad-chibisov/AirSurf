#import "BrowserTabOverviewController.h"

#import "BrowserTabViewModel.h"
#import "BrowserTheme.h"
#import "BrowserViewModel.h"

static NSString * const kTabCellIdentifier = @"BrowserTabCardCell";
// Three columns on the tvOS grid (80 pt margins, 40 pt gutters). At most six cards, so both rows
// fit between the title and the hint without scrolling.
static CGFloat const kTabCardWidth = 560.0;
static CGFloat const kTabCardImageHeight = 292.0;
static CGFloat const kTabCardHeight = 378.0;

@interface BrowserTabCardCell : UICollectionViewCell

@property (nonatomic) UIView *cardView;
@property (nonatomic) UIImageView *snapshotView;
@property (nonatomic) UIImageView *symbolView;
@property (nonatomic) UILabel *titleLabel;
@property (nonatomic) UILabel *detailLabel;

@end

@implementation BrowserTabCardCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.clipsToBounds = NO;
        self.contentView.clipsToBounds = NO;

        _cardView = [[UIView alloc] initWithFrame:CGRectZero];
        _cardView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
        _cardView.layer.cornerRadius = 26.0;
        _cardView.layer.cornerCurve = kCACornerCurveContinuous;
        _cardView.layer.shadowColor = UIColor.blackColor.CGColor;
        _cardView.layer.shadowOffset = CGSizeMake(0.0, 20.0);
        _cardView.layer.shadowRadius = 30.0;
        _cardView.layer.shadowOpacity = 0.0;
        [self.contentView addSubview:_cardView];

        _snapshotView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _snapshotView.contentMode = UIViewContentModeScaleAspectFill;
        _snapshotView.clipsToBounds = YES;
        _snapshotView.layer.cornerRadius = 26.0;
        _snapshotView.layer.cornerCurve = kCACornerCurveContinuous;
        [_cardView addSubview:_snapshotView];

        _symbolView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _symbolView.contentMode = UIViewContentModeCenter;
        _symbolView.tintColor = [UIColor colorWithWhite:1.0 alpha:0.7];
        [_cardView addSubview:_symbolView];

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.font = [BrowserTheme fontForTextStyle:UIFontTextStyleBody emphasized:NO];
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:_titleLabel];

        _detailLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _detailLabel.font = [BrowserTheme fontForTextStyle:UIFontTextStyleCaption2 emphasized:NO];
        _detailLabel.textAlignment = NSTextAlignmentCenter;
        _detailLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [self.contentView addSubview:_detailLabel];

        [self applyFocusAppearance];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    CGAffineTransform transform = self.cardView.transform;
    self.cardView.transform = CGAffineTransformIdentity;
    self.cardView.frame = CGRectMake(0.0, 0.0, width, kTabCardImageHeight);
    self.cardView.transform = transform;
    self.snapshotView.frame = self.cardView.bounds;
    self.symbolView.frame = self.cardView.bounds;
    self.titleLabel.frame = CGRectMake(0.0, kTabCardImageHeight + 22.0, width, 36.0);
    self.detailLabel.frame = CGRectMake(0.0, kTabCardImageHeight + 56.0, width, 30.0);
}

- (void)configureWithTab:(BrowserTabViewModel *)tab isActive:(BOOL)isActive {
    BOOL isStartPage = tab.showsStartPage || tab.URLString.length == 0;
    self.snapshotView.image = isStartPage ? nil : tab.snapshotImage;
    self.symbolView.image = self.snapshotView.image == nil
        ? [BrowserTheme symbolNamed:isStartPage ? @"square.grid.2x2" : @"globe" pointSize:64.0 weight:UIImageSymbolWeightRegular]
        : nil;
    self.titleLabel.text = isStartPage ? @"Start Page" : (tab.title.length > 0 ? tab.title : @"Untitled");
    NSString *host = [NSURL URLWithString:tab.URLString].host ?: @"";
    if ([host hasPrefix:@"www."]) {
        host = [host substringFromIndex:4];
    }
    self.detailLabel.text = isActive ? (host.length > 0 ? [NSString stringWithFormat:@"%@ · Current", host] : @"Current") : host;
    self.accessibilityLabel = self.titleLabel.text;
}

- (void)configureAsNewTab {
    self.snapshotView.image = nil;
    self.symbolView.image = [BrowserTheme symbolNamed:@"plus" pointSize:72.0 weight:UIImageSymbolWeightRegular];
    self.titleLabel.text = @"New Tab";
    self.detailLabel.text = @"";
    self.accessibilityLabel = @"New Tab";
}

- (void)applyFocusAppearance {
    BOOL focused = self.focused;
    self.cardView.transform = focused ? CGAffineTransformMakeScale(1.08, 1.08) : CGAffineTransformIdentity;
    self.cardView.layer.shadowOpacity = focused ? 0.6 : 0.0;
    self.cardView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:focused ? 0.2 : 0.08];
    self.symbolView.tintColor = [UIColor colorWithWhite:1.0 alpha:focused ? 1.0 : 0.6];
    self.titleLabel.textColor = focused ? UIColor.whiteColor : [UIColor colorWithWhite:1.0 alpha:0.75];
    self.detailLabel.textColor = [UIColor colorWithWhite:1.0 alpha:focused ? 0.7 : 0.45];
    CGAffineTransform labelShift = focused ? CGAffineTransformMakeTranslation(0.0, 12.0) : CGAffineTransformIdentity;
    self.titleLabel.transform = labelShift;
    self.detailLabel.transform = labelShift;
}

- (void)didUpdateFocusInContext:(UIFocusUpdateContext *)context withAnimationCoordinator:(UIFocusAnimationCoordinator *)coordinator {
    [super didUpdateFocusInContext:context withAnimationCoordinator:coordinator];
    [coordinator addCoordinatedAnimations:^{
        [self applyFocusAppearance];
    } completion:nil];
}

@end

@interface BrowserTabOverviewController () <UICollectionViewDataSource, UICollectionViewDelegate>

@property (nonatomic) BrowserViewModel *viewModel;
@property (nonatomic) UICollectionView *collectionView;
@property (nonatomic) UILabel *titleLabel;
@property (nonatomic) UILabel *hintLabel;
@property (nonatomic) NSIndexPath *preferredIndexPath;
@property (nonatomic) BOOL handlingRemotePress;

@end

@implementation BrowserTabOverviewController

- (instancetype)initWithViewModel:(BrowserViewModel *)viewModel {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _viewModel = viewModel;
        self.modalPresentationStyle = UIModalPresentationOverFullScreen;
        self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    }
    return self;
}

- (BOOL)canAddTab {
    return self.viewModel.tabs.count < [BrowserViewModel maximumTabCount];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    UIVisualEffectView *backdrop = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    backdrop.frame = self.view.bounds;
    backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:backdrop];
    UIView *scrim = [[UIView alloc] initWithFrame:self.view.bounds];
    scrim.autoresizingMask = backdrop.autoresizingMask;
    scrim.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.35];
    [self.view addSubview:scrim];

    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(80.0, 60.0, 800.0, 66.0)];
    self.titleLabel.font = [BrowserTheme fontForTextStyle:UIFontTextStyleTitle2 emphasized:YES];
    self.titleLabel.textColor = [BrowserTheme primaryTextColor];
    self.titleLabel.text = @"Tabs";
    [self.view addSubview:self.titleLabel];

    self.hintLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.hintLabel.font = [BrowserTheme fontForTextStyle:UIFontTextStyleCaption1 emphasized:NO];
    self.hintLabel.textColor = [BrowserTheme secondaryTextColor];
    self.hintLabel.textAlignment = NSTextAlignmentCenter;
    self.hintLabel.text = @"Press Play/Pause to close the highlighted tab";
    [self.view addSubview:self.hintLabel];

    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    layout.itemSize = CGSizeMake(kTabCardWidth, kTabCardHeight);
    layout.minimumInteritemSpacing = 40.0;
    layout.minimumLineSpacing = 40.0;
    layout.sectionInset = UIEdgeInsetsMake(24.0, 80.0, 20.0, 80.0);

    self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.collectionView.backgroundColor = UIColor.clearColor;
    self.collectionView.dataSource = self;
    self.collectionView.delegate = self;
    self.collectionView.clipsToBounds = NO;
    self.collectionView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    [self.collectionView registerClass:[BrowserTabCardCell class] forCellWithReuseIdentifier:kTabCellIdentifier];
    [self.view addSubview:self.collectionView];

    NSInteger activeIndex = self.viewModel.activeTabIndex;
    if (activeIndex != NSNotFound && activeIndex >= 0 && activeIndex < (NSInteger)self.viewModel.tabs.count) {
        self.preferredIndexPath = [NSIndexPath indexPathForItem:activeIndex inSection:0];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect bounds = self.view.bounds;
    CGFloat top = CGRectGetMaxY(self.titleLabel.frame);
    CGFloat hintY = CGRectGetHeight(bounds) - 96.0;
    self.collectionView.frame = CGRectMake(0.0, top, CGRectGetWidth(bounds), hintY - top);
    self.hintLabel.frame = CGRectMake(0.0, hintY, CGRectGetWidth(bounds), 36.0);
}

- (void)reloadTabs {
    if (!self.isViewLoaded) {
        return;
    }
    [self.collectionView reloadData];
    [self setNeedsFocusUpdate];
}

- (void)reloadTabAtIndex:(NSInteger)tabIndex {
    if (!self.isViewLoaded || tabIndex < 0 || tabIndex >= (NSInteger)self.viewModel.tabs.count) {
        return;
    }
    NSIndexPath *indexPath = [NSIndexPath indexPathForItem:tabIndex inSection:0];
    BrowserTabCardCell *cell = (BrowserTabCardCell *)[self.collectionView cellForItemAtIndexPath:indexPath];
    [cell configureWithTab:self.viewModel.tabs[(NSUInteger)tabIndex] isActive:tabIndex == self.viewModel.activeTabIndex];
}

#pragma mark Collection view

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return (NSInteger)self.viewModel.tabs.count + ([self canAddTab] ? 1 : 0);
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    BrowserTabCardCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:kTabCellIdentifier forIndexPath:indexPath];
    if (indexPath.item < (NSInteger)self.viewModel.tabs.count) {
        [cell configureWithTab:self.viewModel.tabs[(NSUInteger)indexPath.item] isActive:indexPath.item == self.viewModel.activeTabIndex];
    } else {
        [cell configureAsNewTab];
    }
    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.item < (NSInteger)self.viewModel.tabs.count) {
        [self.delegate tabOverviewController:self didSelectTabAtIndex:indexPath.item];
    } else {
        [self.delegate tabOverviewControllerDidRequestNewTab:self];
    }
}

- (NSIndexPath *)indexPathForPreferredFocusedViewInCollectionView:(UICollectionView *)collectionView {
    return self.preferredIndexPath;
}

- (NSArray<id<UIFocusEnvironment>> *)preferredFocusEnvironments {
    return @[self.collectionView];
}

- (void)closeFocusedTab {
    UIView *focusedView = (UIView *)[UIFocusSystem focusSystemForEnvironment:self].focusedItem;
    if (![focusedView isKindOfClass:[UICollectionViewCell class]]) {
        return;
    }
    NSIndexPath *indexPath = [self.collectionView indexPathForCell:(UICollectionViewCell *)focusedView];
    if (indexPath == nil || indexPath.item >= (NSInteger)self.viewModel.tabs.count) {
        return;
    }
    [self.delegate tabOverviewController:self didCloseTabAtIndex:indexPath.item];
    NSInteger remaining = (NSInteger)self.viewModel.tabs.count;
    self.preferredIndexPath = [NSIndexPath indexPathForItem:MAX(0, MIN(indexPath.item, remaining - 1)) inSection:0];
    [self.collectionView reloadData];
    [self setNeedsFocusUpdate];
    [self updateFocusIfNeeded];
}

#pragma mark Presses

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
        self.handlingRemotePress = YES;
        return;
    }
    [super pressesBegan:presses withEvent:event];
}

- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    if ([self pressesContainMenuOrPlayPause:presses]) {
        BOOL wasHandling = self.handlingRemotePress;
        self.handlingRemotePress = NO;
        if (!wasHandling) {
            return;
        }
        for (UIPress *press in presses) {
            if (press.type == UIPressTypeMenu) {
                [self dismissViewControllerAnimated:YES completion:nil];
                return;
            }
        }
        [self closeFocusedTab];
        return;
    }
    [super pressesEnded:presses withEvent:event];
}

- (void)pressesCancelled:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    if ([self pressesContainMenuOrPlayPause:presses]) {
        self.handlingRemotePress = NO;
        return;
    }
    [super pressesCancelled:presses withEvent:event];
}

@end
