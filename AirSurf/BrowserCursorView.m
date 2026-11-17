#import "BrowserCursorView.h"

#import "BrowserTheme.h"

static CGFloat const kCursorCanvasSide = 72.0;
static CGFloat const kCursorDotSide = 30.0;
static CGFloat const kCursorScrollSide = 60.0;

@interface BrowserCursorView ()

@property (nonatomic) UIView *dotView;
@property (nonatomic) UIImageView *glyphView;

@end

@implementation BrowserCursorView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:CGRectMake(frame.origin.x, frame.origin.y, kCursorCanvasSide, kCursorCanvasSide)];
    if (self) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = UIColor.clearColor;

        _dotView = [[UIView alloc] initWithFrame:CGRectZero];
        _dotView.layer.borderWidth = 2.0;
        _dotView.layer.shadowColor = UIColor.blackColor.CGColor;
        _dotView.layer.shadowOpacity = 0.45;
        _dotView.layer.shadowRadius = 5.0;
        _dotView.layer.shadowOffset = CGSizeMake(0.0, 2.0);
        [self addSubview:_dotView];

        _glyphView = [[UIImageView alloc] initWithImage:[BrowserTheme symbolNamed:@"arrow.up.and.down" pointSize:26.0 weight:UIImageSymbolWeightBold]];
        _glyphView.tintColor = UIColor.whiteColor;
        _glyphView.contentMode = UIViewContentModeCenter;
        _glyphView.alpha = 0.0;
        [self addSubview:_glyphView];

        [self applyAppearance];
    }
    return self;
}

- (void)setStyle:(BrowserCursorStyle)style {
    if (_style == style) {
        return;
    }
    _style = style;
    [BrowserTheme animateQuick:^{
        [self applyAppearance];
    }];
}

- (void)setPressed:(BOOL)pressed {
    if (_pressed == pressed) {
        return;
    }
    _pressed = pressed;
    // Feedback on press-down, not on release.
    [BrowserTheme animateQuick:^{
        [self applyAppearance];
    }];
}

- (void)applyAppearance {
    CGFloat side = kCursorDotSide;
    UIColor *fill = [UIColor colorWithWhite:1.0 alpha:0.92];
    UIColor *border = [UIColor colorWithWhite:0.0 alpha:0.38];
    CGFloat glyphAlpha = 0.0;

    switch (self.style) {
        case BrowserCursorStyleLink:
            side = 40.0;
            fill = [[BrowserTheme accentColor] colorWithAlphaComponent:0.9];
            border = [UIColor colorWithWhite:1.0 alpha:0.95];
            break;
        case BrowserCursorStyleScroll:
            side = kCursorScrollSide;
            fill = [UIColor colorWithWhite:0.08 alpha:0.78];
            border = [UIColor colorWithWhite:1.0 alpha:0.5];
            glyphAlpha = 1.0;
            break;
        case BrowserCursorStyleDefault:
            break;
    }
    if (self.pressed) {
        side *= 0.78;
    }

    CGPoint center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    self.dotView.bounds = CGRectMake(0.0, 0.0, side, side);
    self.dotView.center = center;
    self.dotView.layer.cornerRadius = side / 2.0;
    self.dotView.backgroundColor = fill;
    self.dotView.layer.borderColor = border.CGColor;
    self.glyphView.frame = self.bounds;
    self.glyphView.alpha = glyphAlpha;
}

@end
