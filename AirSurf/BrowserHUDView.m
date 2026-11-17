#import "BrowserHUDView.h"

#import "BrowserTheme.h"

static CGFloat const kHUDHeight = 72.0;
static CGFloat const kHUDBottomInset = 84.0;

@interface BrowserHUDView ()

@property (nonatomic) UIVisualEffectView *capsuleView;
@property (nonatomic) UIImageView *symbolView;
@property (nonatomic) UILabel *label;
@property (nonatomic) NSUInteger generation;

@end

@implementation BrowserHUDView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = UIColor.clearColor;

        _capsuleView = [[UIVisualEffectView alloc] initWithEffect:[BrowserTheme chromeEffect]];
        _capsuleView.clipsToBounds = YES;
        _capsuleView.layer.cornerRadius = kHUDHeight / 2.0;
        _capsuleView.layer.cornerCurve = kCACornerCurveContinuous;
        _capsuleView.alpha = 0.0;
        [self addSubview:_capsuleView];

        _symbolView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _symbolView.tintColor = [BrowserTheme primaryTextColor];
        _symbolView.contentMode = UIViewContentModeCenter;
        [_capsuleView.contentView addSubview:_symbolView];

        _label = [[UILabel alloc] initWithFrame:CGRectZero];
        _label.font = [BrowserTheme fontForTextStyle:UIFontTextStyleBody emphasized:YES];
        _label.textColor = [BrowserTheme primaryTextColor];
        _label.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [_capsuleView.contentView addSubview:_label];
    }
    return self;
}

- (void)layoutCapsule {
    CGFloat maxLabelWidth = CGRectGetWidth(self.bounds) - 400.0;
    CGSize labelSize = [self.label sizeThatFits:CGSizeMake(maxLabelWidth, kHUDHeight)];
    labelSize.width = MIN(labelSize.width, maxLabelWidth);
    BOOL hasSymbol = self.symbolView.image != nil;
    CGFloat symbolWidth = hasSymbol ? 40.0 : 0.0;
    CGFloat gap = hasSymbol ? 14.0 : 0.0;
    CGFloat width = 32.0 + symbolWidth + gap + ceil(labelSize.width) + 36.0;
    self.capsuleView.bounds = CGRectMake(0.0, 0.0, width, kHUDHeight);
    self.capsuleView.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetHeight(self.bounds) - kHUDBottomInset - kHUDHeight / 2.0);
    self.symbolView.frame = CGRectMake(32.0, 0.0, symbolWidth, kHUDHeight);
    self.label.frame = CGRectMake(32.0 + symbolWidth + gap, 0.0, ceil(labelSize.width), kHUDHeight);
}

- (void)presentMessage:(NSString *)message symbolName:(NSString *)symbolName persistent:(BOOL)persistent {
    self.generation += 1;
    NSUInteger generation = self.generation;

    self.label.text = message;
    self.symbolView.image = symbolName.length > 0 ? [BrowserTheme symbolNamed:symbolName pointSize:28.0 weight:UIImageSymbolWeightSemibold] : nil;
    BOOL wasHidden = self.capsuleView.alpha < 0.01;
    [self layoutCapsule];
    if (wasHidden) {
        self.capsuleView.transform = CGAffineTransformMakeTranslation(0.0, 36.0);
    }
    [BrowserTheme animate:^{
        self.capsuleView.alpha = 1.0;
        self.capsuleView.transform = CGAffineTransformIdentity;
    }];

    if (persistent) {
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.generation == generation) {
            [self hide];
        }
    });
}

- (void)showMessage:(NSString *)message symbolName:(NSString *)symbolName {
    [self presentMessage:message symbolName:symbolName persistent:NO];
}

- (void)showPersistentMessage:(NSString *)message symbolName:(NSString *)symbolName {
    [self presentMessage:message symbolName:symbolName persistent:YES];
}

- (void)hide {
    self.generation += 1;
    // Leaves the way it arrived.
    [BrowserTheme animate:^{
        self.capsuleView.alpha = 0.0;
        self.capsuleView.transform = CGAffineTransformMakeTranslation(0.0, 36.0);
    }];
}

@end
