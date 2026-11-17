#import "BrowserTopBarView.h"

#import "BrowserTheme.h"

static CGFloat const kBarTopInset = 22.0;
static CGFloat const kBarHeight = 72.0;
static CGFloat const kBarBottomGap = 12.0;
static CGFloat const kBarSideInset = 80.0;
static CGFloat const kBarPadding = 8.0;
static CGFloat const kBarButtonSide = 56.0;
static CGFloat const kBarButtonSpacing = 6.0;

#pragma mark - Button

@interface BrowserBarButton : UIControl

@property (nonatomic) BrowserTopBarAction action;
@property (nonatomic) UIView *plateView;
@property (nonatomic) UIImageView *iconView;
@property (nonatomic) UILabel *textLabel;
@property (nonatomic) BOOL focusEnabled;
@property (nonatomic, getter=isHovered) BOOL hovered;
@property (nonatomic) UIColor *restingTintColor;

@end

@implementation BrowserBarButton

- (instancetype)initWithAction:(BrowserTopBarAction)action symbolName:(NSString *)symbolName accessibilityLabel:(NSString *)accessibilityLabel {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _action = action;
        _restingTintColor = [BrowserTheme primaryTextColor];
        self.accessibilityLabel = accessibilityLabel;
        self.accessibilityTraits = UIAccessibilityTraitButton;
        self.isAccessibilityElement = YES;

        _plateView = [[UIView alloc] initWithFrame:CGRectZero];
        _plateView.userInteractionEnabled = NO;
        _plateView.backgroundColor = UIColor.whiteColor;
        _plateView.alpha = 0.0;
        _plateView.layer.cornerCurve = kCACornerCurveContinuous;
        [self addSubview:_plateView];

        _iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _iconView.contentMode = UIViewContentModeCenter;
        _iconView.tintColor = _restingTintColor;
        [self addSubview:_iconView];
        if (symbolName.length > 0) {
            [self setSymbolName:symbolName];
        }
    }
    return self;
}

- (void)setSymbolName:(NSString *)symbolName {
    self.iconView.image = [BrowserTheme symbolNamed:symbolName pointSize:26.0 weight:UIImageSymbolWeightSemibold];
}

- (BOOL)canBecomeFocused {
    return self.focusEnabled && self.enabled && !self.hidden;
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    [self applyAppearance];
}

- (void)setHovered:(BOOL)hovered {
    if (_hovered == hovered) {
        return;
    }
    _hovered = hovered;
    [BrowserTheme animateQuick:^{
        [self applyAppearance];
    }];
}

- (void)setRestingTintColor:(UIColor *)restingTintColor {
    _restingTintColor = restingTintColor;
    [self applyAppearance];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.plateView.frame = self.bounds;
    self.plateView.layer.cornerRadius = CGRectGetHeight(self.bounds) / 2.0;
    if (self.textLabel == nil) {
        self.iconView.frame = self.bounds;
    }
}

- (void)applyAppearance {
    BOOL lifted = (self.focused || self.hovered) && self.enabled;
    self.plateView.alpha = lifted ? 1.0 : 0.0;
    UIColor *tint = lifted ? [UIColor colorWithWhite:0.08 alpha:1.0] : self.restingTintColor;
    self.iconView.tintColor = tint;
    self.textLabel.textColor = tint;
    self.alpha = self.enabled ? 1.0 : 0.32;
    self.transform = lifted ? CGAffineTransformMakeScale(1.08, 1.08) : CGAffineTransformIdentity;
}

- (void)didUpdateFocusInContext:(UIFocusUpdateContext *)context withAnimationCoordinator:(UIFocusAnimationCoordinator *)coordinator {
    [super didUpdateFocusInContext:context withAnimationCoordinator:coordinator];
    [coordinator addCoordinatedAnimations:^{
        [self applyAppearance];
    } completion:nil];
}

- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    for (UIPress *press in presses) {
        if (press.type == UIPressTypeSelect && self.focused) {
            [self sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
            return;
        }
    }
    [super pressesEnded:presses withEvent:event];
}

@end

#pragma mark - Address field

@interface BrowserAddressControl : BrowserBarButton

@property (nonatomic) UILabel *hostLabel;
@property (nonatomic) UILabel *titleLabel;
@property (nonatomic) UIView *progressView;
@property (nonatomic) double progress;
@property (nonatomic) BOOL showsProgress;

@end

@implementation BrowserAddressControl

- (instancetype)init {
    self = [super initWithAction:BrowserTopBarActionAddress symbolName:@"magnifyingglass" accessibilityLabel:@"Search or enter website"];
    if (self) {
        self.plateView.layer.cornerRadius = 0.0;

        _hostLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _hostLabel.font = [UIFont systemFontOfSize:29.0 weight:UIFontWeightSemibold];
        _hostLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [self addSubview:_hostLabel];

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.font = [UIFont systemFontOfSize:27.0 weight:UIFontWeightRegular];
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:_titleLabel];

        _progressView = [[UIView alloc] initWithFrame:CGRectZero];
        _progressView.backgroundColor = [BrowserTheme accentColor];
        _progressView.userInteractionEnabled = NO;
        _progressView.alpha = 0.0;
        [self addSubview:_progressView];

        self.clipsToBounds = NO;
        [self applyAppearance];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat height = CGRectGetHeight(self.bounds);
    CGFloat width = CGRectGetWidth(self.bounds);
    self.plateView.frame = self.bounds;
    self.plateView.layer.cornerRadius = height / 2.0;

    CGFloat iconWidth = 44.0;
    CGFloat contentInset = 16.0;
    CGFloat available = width - contentInset * 2.0 - iconWidth - 10.0;
    CGSize hostSize = [self.hostLabel sizeThatFits:CGSizeMake(available, height)];
    CGSize titleSize = [self.titleLabel sizeThatFits:CGSizeMake(available, height)];
    CGFloat hostWidth = MIN(ceil(hostSize.width), available);
    CGFloat gap = (hostWidth > 0.0 && titleSize.width > 0.0) ? 18.0 : 0.0;
    CGFloat titleWidth = MAX(0.0, MIN(ceil(titleSize.width), available - hostWidth - gap));
    if (titleWidth < 80.0) {
        titleWidth = 0.0;
        gap = 0.0;
    }
    CGFloat contentWidth = iconWidth + 10.0 + hostWidth + gap + titleWidth;
    CGFloat originX = MAX(contentInset, floor((width - contentWidth) / 2.0));
    self.iconView.frame = CGRectMake(originX, 0.0, iconWidth, height);
    self.hostLabel.frame = CGRectMake(originX + iconWidth + 10.0, 0.0, hostWidth, height);
    self.titleLabel.frame = CGRectMake(CGRectGetMaxX(self.hostLabel.frame) + gap, 0.0, titleWidth, height);
    [self layoutProgress];
}

- (void)layoutProgress {
    CGFloat height = CGRectGetHeight(self.bounds);
    CGFloat inset = height / 2.0;
    CGFloat track = MAX(0.0, CGRectGetWidth(self.bounds) - inset * 2.0);
    self.progressView.frame = CGRectMake(inset, height - 5.0, track * MIN(1.0, MAX(0.0, self.progress)), 3.0);
    self.progressView.layer.cornerRadius = 1.5;
}

- (void)setProgress:(double)progress {
    BOOL movingForward = progress > _progress;
    _progress = progress;
    if (movingForward) {
        [BrowserTheme animateQuick:^{
            [self layoutProgress];
        }];
    } else {
        [self layoutProgress];
    }
}

- (void)setShowsProgress:(BOOL)showsProgress {
    if (_showsProgress == showsProgress) {
        return;
    }
    _showsProgress = showsProgress;
    [UIView animateWithDuration:showsProgress ? 0.12 : 0.35
                          delay:showsProgress ? 0.0 : 0.15
                        options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        self.progressView.alpha = showsProgress ? 1.0 : 0.0;
    } completion:nil];
}

- (void)applyAppearance {
    BOOL lifted = (self.focused || self.hovered) && self.enabled;
    self.plateView.alpha = lifted ? 1.0 : 0.0;
    self.iconView.tintColor = lifted ? [UIColor colorWithWhite:0.08 alpha:0.7] : [BrowserTheme secondaryTextColor];
    self.hostLabel.textColor = lifted ? [UIColor colorWithWhite:0.05 alpha:1.0] : [BrowserTheme primaryTextColor];
    self.titleLabel.textColor = lifted ? [UIColor colorWithWhite:0.05 alpha:0.6] : [BrowserTheme secondaryTextColor];
    self.transform = lifted ? CGAffineTransformMakeScale(1.02, 1.02) : CGAffineTransformIdentity;
}

@end

#pragma mark - Top bar

@interface BrowserTopBarView ()

@property (nonatomic) UIVisualEffectView *capsuleView;
@property (nonatomic) BrowserBarButton *backButton;
@property (nonatomic) BrowserBarButton *forwardButton;
@property (nonatomic) BrowserBarButton *reloadButton;
@property (nonatomic) BrowserAddressControl *addressControl;
@property (nonatomic) BrowserBarButton *favoriteButton;
@property (nonatomic) BrowserBarButton *tabsButton;
@property (nonatomic) BrowserBarButton *menuButton;
@property (nonatomic) NSArray<BrowserBarButton *> *controls;
@property (nonatomic) NSMutableArray<UIFocusGuide *> *focusGuides;

@end

@implementation BrowserTopBarView

+ (CGFloat)preferredHeight {
    return kBarTopInset + kBarHeight + kBarBottomGap;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        _pageActionsEnabled = YES;

        _capsuleView = [[UIVisualEffectView alloc] initWithEffect:[BrowserTheme chromeEffect]];
        _capsuleView.clipsToBounds = YES;
        _capsuleView.layer.cornerRadius = kBarHeight / 2.0;
        _capsuleView.layer.cornerCurve = kCACornerCurveContinuous;
        if ([BrowserTheme usesLightweightMaterials]) {
            // A plain blur has no edge of its own; a hairline keeps the bar readable on dark pages.
            _capsuleView.layer.borderWidth = 1.0;
            _capsuleView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.16].CGColor;
        }
        [self addSubview:_capsuleView];

        _backButton = [[BrowserBarButton alloc] initWithAction:BrowserTopBarActionBack symbolName:@"chevron.backward" accessibilityLabel:@"Back"];
        _forwardButton = [[BrowserBarButton alloc] initWithAction:BrowserTopBarActionForward symbolName:@"chevron.forward" accessibilityLabel:@"Forward"];
        _reloadButton = [[BrowserBarButton alloc] initWithAction:BrowserTopBarActionReload symbolName:@"arrow.clockwise" accessibilityLabel:@"Reload"];
        _addressControl = [BrowserAddressControl new];
        _favoriteButton = [[BrowserBarButton alloc] initWithAction:BrowserTopBarActionFavorite symbolName:@"star" accessibilityLabel:@"Add to Favorites"];
        _tabsButton = [[BrowserBarButton alloc] initWithAction:BrowserTopBarActionTabs symbolName:@"square.on.square" accessibilityLabel:@"Tabs"];
        _menuButton = [[BrowserBarButton alloc] initWithAction:BrowserTopBarActionMenu symbolName:@"ellipsis" accessibilityLabel:@"Menu"];

        UILabel *tabCountLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        tabCountLabel.font = [UIFont monospacedDigitSystemFontOfSize:25.0 weight:UIFontWeightSemibold];
        tabCountLabel.textAlignment = NSTextAlignmentLeft;
        [_tabsButton addSubview:tabCountLabel];
        _tabsButton.textLabel = tabCountLabel;

        _controls = @[_backButton, _forwardButton, _reloadButton, _addressControl, _favoriteButton, _tabsButton, _menuButton];
        for (BrowserBarButton *control in _controls) {
            [control addTarget:self action:@selector(handleControl:) forControlEvents:UIControlEventPrimaryActionTriggered];
            [_capsuleView.contentView addSubview:control];
        }
        _focusGuides = [NSMutableArray array];

        [self setTitle:nil URLString:nil];
        [self refreshControls];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = CGRectGetWidth(self.bounds) - kBarSideInset * 2.0;
    self.capsuleView.frame = CGRectMake(kBarSideInset, kBarTopInset, MAX(width, 600.0), kBarHeight);

    CGFloat buttonY = (kBarHeight - kBarButtonSide) / 2.0;
    CGFloat x = kBarPadding;
    for (BrowserBarButton *button in @[self.backButton, self.forwardButton, self.reloadButton]) {
        button.frame = CGRectMake(x, buttonY, kBarButtonSide, kBarButtonSide);
        x += kBarButtonSide + kBarButtonSpacing;
    }
    CGFloat leadingEdge = x + 6.0;

    CGFloat tabsWidth = kBarButtonSide + 34.0;
    CGFloat right = CGRectGetWidth(self.capsuleView.bounds) - kBarPadding;
    self.menuButton.frame = CGRectMake(right - kBarButtonSide, buttonY, kBarButtonSide, kBarButtonSide);
    right = CGRectGetMinX(self.menuButton.frame) - kBarButtonSpacing;
    self.tabsButton.frame = CGRectMake(right - tabsWidth, buttonY, tabsWidth, kBarButtonSide);
    right = CGRectGetMinX(self.tabsButton.frame) - kBarButtonSpacing;
    self.favoriteButton.frame = CGRectMake(right - kBarButtonSide, buttonY, kBarButtonSide, kBarButtonSide);
    CGFloat trailingEdge = CGRectGetMinX(self.favoriteButton.frame) - 6.0 - kBarButtonSpacing;

    self.addressControl.frame = CGRectMake(leadingEdge, buttonY, MAX(200.0, trailingEdge - leadingEdge), kBarButtonSide);

    self.tabsButton.iconView.frame = CGRectMake(10.0, 0.0, 44.0, kBarButtonSide);
    self.tabsButton.textLabel.frame = CGRectMake(56.0, 0.0, tabsWidth - 60.0, kBarButtonSide);
}

#pragma mark State

- (void)refreshControls {
    self.backButton.enabled = self.canGoBack;
    self.forwardButton.enabled = self.canGoForward;
    self.reloadButton.enabled = self.pageActionsEnabled;
    self.favoriteButton.enabled = self.pageActionsEnabled;
    [self.reloadButton setSymbolName:self.loading ? @"xmark" : @"arrow.clockwise"];
    self.reloadButton.accessibilityLabel = self.loading ? @"Stop" : @"Reload";
    [self.favoriteButton setSymbolName:self.favorite ? @"star.fill" : @"star"];
    self.favoriteButton.accessibilityLabel = self.favorite ? @"Remove from Favorites" : @"Add to Favorites";
    self.favoriteButton.restingTintColor = self.favorite ? [UIColor colorWithRed:1.0 green:0.8 blue:0.2 alpha:1.0] : [BrowserTheme primaryTextColor];
    self.tabsButton.textLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)MAX(self.tabCount, (NSUInteger)1)];
    self.addressControl.showsProgress = self.loading;
}

- (void)setCanGoBack:(BOOL)canGoBack { _canGoBack = canGoBack; [self refreshControls]; }
- (void)setCanGoForward:(BOOL)canGoForward { _canGoForward = canGoForward; [self refreshControls]; }
- (void)setLoading:(BOOL)loading { _loading = loading; [self refreshControls]; }
- (void)setFavorite:(BOOL)favorite { _favorite = favorite; [self refreshControls]; }
- (void)setPageActionsEnabled:(BOOL)pageActionsEnabled { _pageActionsEnabled = pageActionsEnabled; [self refreshControls]; }
- (void)setTabCount:(NSUInteger)tabCount { _tabCount = tabCount; [self refreshControls]; }

- (void)setProgress:(double)progress {
    _progress = progress;
    self.addressControl.progress = progress;
}

- (void)setFocusEnabled:(BOOL)focusEnabled {
    _focusEnabled = focusEnabled;
    for (BrowserBarButton *control in self.controls) {
        control.focusEnabled = focusEnabled;
    }
    if (!focusEnabled) {
        [self clearHover];
    }
}

- (void)setTitle:(NSString *)title URLString:(NSString *)URLString {
    NSURL *URL = URLString.length > 0 ? [NSURL URLWithString:URLString] : nil;
    NSString *host = URL.host ?: @"";
    if ([host hasPrefix:@"www."]) {
        host = [host substringFromIndex:4];
    }
    NSString *trimmedTitle = [title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";

    if (host.length == 0 && URLString.length == 0) {
        self.addressControl.hostLabel.text = @"Search or enter website";
        self.addressControl.titleLabel.text = @"";
        [self.addressControl setSymbolName:@"magnifyingglass"];
    } else {
        self.addressControl.hostLabel.text = host.length > 0 ? host : URLString;
        self.addressControl.titleLabel.text = [trimmedTitle isEqualToString:host] ? @"" : trimmedTitle;
        BOOL secure = [URL.scheme.lowercaseString isEqualToString:@"https"];
        [self.addressControl setSymbolName:secure ? @"lock.fill" : @"globe"];
    }
    self.addressControl.accessibilityValue = URLString;
    [self.addressControl setNeedsLayout];
}

- (UIView *)addressFocusItem {
    return self.addressControl;
}

#pragma mark Actions

- (void)handleControl:(BrowserBarButton *)control {
    [self.delegate browserTopBarView:self didTriggerAction:control.action];
}

- (BrowserBarButton *)controlAtPoint:(CGPoint)point {
    CGPoint capsulePoint = [self convertPoint:point toView:self.capsuleView.contentView];
    for (BrowserBarButton *control in self.controls) {
        // A little slop around each control: the cursor is coarse at ten feet.
        if (CGRectContainsPoint(CGRectInset(control.frame, -4.0, -8.0), capsulePoint)) {
            return control;
        }
    }
    return nil;
}

- (BOOL)updateHoverAtPoint:(CGPoint)point {
    BrowserBarButton *hoveredControl = [self controlAtPoint:point];
    BOOL hoveringEnabledControl = NO;
    for (BrowserBarButton *control in self.controls) {
        BOOL hovered = (control == hoveredControl) && control.enabled;
        control.hovered = hovered;
        hoveringEnabledControl = hoveringEnabledControl || hovered;
    }
    return hoveringEnabledControl;
}

- (BOOL)activateAtPoint:(CGPoint)point {
    BrowserBarButton *control = [self controlAtPoint:point];
    if (control == nil || !control.enabled) {
        return NO;
    }
    [self.delegate browserTopBarView:self didTriggerAction:control.action];
    return YES;
}

- (void)clearHover {
    for (BrowserBarButton *control in self.controls) {
        control.hovered = NO;
    }
}

- (NSArray<id<UIFocusEnvironment>> *)preferredFocusEnvironments {
    return @[self.addressControl];
}

@end
