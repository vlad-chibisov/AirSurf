#import "BrowserRemoteInputController.h"

#import "BrowserCursorView.h"

static NSTimeInterval const kHoldDuration = 0.55;
static CGFloat const kScrollGain = 1.6;
static CGFloat const kEdgeScrollGain = 1.8;
static CGFloat const kInertiaDecayPerFrame = 0.955;
static CGFloat const kInertiaMinimumVelocity = 30.0;

@interface BrowserRemoteInputController ()

@property (nonatomic, weak) id<BrowserRemoteInputControllerHost> host;
@property (nonatomic, weak) UIView *rootView;
@property (nonatomic, readwrite) BrowserCursorView *cursorView;

@property (nonatomic) BOOL hasLastTouchLocation;
@property (nonatomic) CGPoint lastTouchLocation;
@property (nonatomic) CFTimeInterval lastTouchTimestamp;
@property (nonatomic) CGPoint scrollVelocity;
@property (nonatomic) CFTimeInterval lastScrollTimestamp;
@property (nonatomic) CADisplayLink *inertiaDisplayLink;
@property (nonatomic) CFTimeInterval inertiaLastTimestamp;
@property (nonatomic) CFTimeInterval lastInnerScrollTimestamp;
@property (nonatomic) CGPoint pendingInnerScroll;

@property (nonatomic) BOOL selectPressActive;
@property (nonatomic) BOOL selectHoldFired;
@property (nonatomic) BOOL playPausePressActive;
@property (nonatomic) BOOL playPauseHoldFired;
@property (nonatomic) BOOL menuPressClaimed;
@property (nonatomic) CFTimeInterval lastDirectSelectTimestamp;
@property (nonatomic) CFTimeInterval pointerActivatedTimestamp;
@property (nonatomic) BOOL pointerWasActive;

@end

@implementation BrowserRemoteInputController

- (instancetype)initWithHost:(id<BrowserRemoteInputControllerHost>)host rootView:(UIView *)rootView {
    self = [super init];
    if (self) {
        _host = host;
        _rootView = rootView;
        _speedMultiplier = 1.0;
        _cursorView = [[BrowserCursorView alloc] initWithFrame:CGRectZero];
        _cursorView.center = CGPointMake(CGRectGetMidX(rootView.bounds), CGRectGetMidY(rootView.bounds));
    }
    return self;
}

- (CGPoint)cursorPoint {
    return self.cursorView.center;
}

#pragma mark State

- (void)refreshPointerState {
    BOOL active = [self.host inputControllerPointerIsActive];
    self.cursorView.hidden = !active;
    if (active && !self.pointerWasActive) {
        self.pointerActivatedTimestamp = CACurrentMediaTime();
    }
    self.pointerWasActive = active;
    if (!active) {
        [self cancelHolds];
        [self stopScrolling];
        self.hasLastTouchLocation = NO;
        self.cursorView.pressed = NO;
    }
}

- (void)setScrollModeEnabled:(BOOL)scrollModeEnabled {
    if (_scrollModeEnabled == scrollModeEnabled) {
        return;
    }
    _scrollModeEnabled = scrollModeEnabled;
    self.hasLastTouchLocation = NO;
    [self stopScrolling];
    self.cursorView.style = scrollModeEnabled ? BrowserCursorStyleScroll : BrowserCursorStyleDefault;
    [self.host inputControllerScrollModeDidChange:scrollModeEnabled];
    if (!scrollModeEnabled) {
        [self.host inputControllerCursorDidMoveToPoint:self.cursorPoint];
    }
}

- (void)setCursorIsOverInteractiveContent:(BOOL)interactive {
    if (self.scrollModeEnabled) {
        return;
    }
    self.cursorView.style = interactive ? BrowserCursorStyleLink : BrowserCursorStyleDefault;
}

- (void)moveCursorToPoint:(CGPoint)point {
    CGRect bounds = self.rootView.bounds;
    point.x = MIN(MAX(point.x, 0.0), CGRectGetWidth(bounds));
    point.y = MIN(MAX(point.y, 0.0), CGRectGetHeight(bounds));
    self.cursorView.center = point;
    [self.host inputControllerCursorDidMoveToPoint:point];
}

#pragma mark Scrolling

/// Scrolls the page by `delta`, returning the part that could not be applied.
- (CGPoint)scrollPageBy:(CGPoint)delta {
    UIScrollView *scrollView = [self.host inputControllerScrollView];
    if (scrollView == nil) {
        return delta;
    }
    CGPoint offset = scrollView.contentOffset;
    CGFloat maxX = MAX(0.0, scrollView.contentSize.width - CGRectGetWidth(scrollView.bounds));
    CGFloat maxY = MAX(0.0, scrollView.contentSize.height - CGRectGetHeight(scrollView.bounds));
    CGPoint target = CGPointMake(MIN(MAX(offset.x + delta.x, 0.0), maxX),
                                 MIN(MAX(offset.y + delta.y, 0.0), maxY));
    if (!CGPointEqualToPoint(target, offset)) {
        [scrollView setContentOffset:target animated:NO];
    }
    return CGPointMake(delta.x - (target.x - offset.x), delta.y - (target.y - offset.y));
}

- (void)scrollBy:(CGPoint)delta trackVelocityWithInterval:(CFTimeInterval)interval {
    CGPoint remainder = [self scrollPageBy:delta];
    if (interval > 0.0005) {
        CGPoint sample = CGPointMake((delta.x - remainder.x) / interval, (delta.y - remainder.y) / interval);
        self.scrollVelocity = CGPointMake(self.scrollVelocity.x * 0.6 + sample.x * 0.4,
                                          self.scrollVelocity.y * 0.6 + sample.y * 0.4);
    }
    self.lastScrollTimestamp = CACurrentMediaTime();

    // What the page itself could not scroll goes to the element under the cursor
    // (an inner list, an embedded frame). Batched, because it crosses into JavaScript.
    if (fabs(remainder.x) > 0.5 || fabs(remainder.y) > 0.5) {
        self.pendingInnerScroll = CGPointMake(self.pendingInnerScroll.x + remainder.x, self.pendingInnerScroll.y + remainder.y);
        CFTimeInterval now = CACurrentMediaTime();
        if (now - self.lastInnerScrollTimestamp > 0.05) {
            self.lastInnerScrollTimestamp = now;
            CGPoint pending = self.pendingInnerScroll;
            self.pendingInnerScroll = CGPointZero;
            [self.host inputControllerScrollInnerContentAtPoint:self.cursorPoint delta:pending];
        }
    }
}

- (void)stopScrolling {
    [self.inertiaDisplayLink invalidate];
    self.inertiaDisplayLink = nil;
    self.scrollVelocity = CGPointZero;
    self.pendingInnerScroll = CGPointZero;
}

- (void)startInertiaIfNeeded {
    CGPoint velocity = self.scrollVelocity;
    BOOL recentlyScrolled = (CACurrentMediaTime() - self.lastScrollTimestamp) < 0.09;
    if (!recentlyScrolled || (fabs(velocity.x) < 120.0 && fabs(velocity.y) < 120.0)) {
        self.scrollVelocity = CGPointZero;
        [self.host inputControllerDidFinishScrolling];
        return;
    }
    [self.inertiaDisplayLink invalidate];
    self.inertiaLastTimestamp = 0.0;
    self.inertiaDisplayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(stepInertia:)];
    [self.inertiaDisplayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)stepInertia:(CADisplayLink *)displayLink {
    if (![self.host inputControllerPointerIsActive]) {
        [self stopScrolling];
        return;
    }
    if (self.inertiaLastTimestamp <= 0.0) {
        self.inertiaLastTimestamp = displayLink.timestamp;
        return;
    }
    CFTimeInterval interval = displayLink.timestamp - self.inertiaLastTimestamp;
    self.inertiaLastTimestamp = displayLink.timestamp;

    CGPoint step = CGPointMake(self.scrollVelocity.x * interval, self.scrollVelocity.y * interval);
    CGPoint remainder = [self scrollPageBy:step];
    BOOL blocked = fabs(remainder.x) >= fabs(step.x) * 0.99 && fabs(remainder.y) >= fabs(step.y) * 0.99;

    CGFloat decay = pow(kInertiaDecayPerFrame, interval * 60.0);
    self.scrollVelocity = CGPointMake(self.scrollVelocity.x * decay, self.scrollVelocity.y * decay);
    if (blocked || (fabs(self.scrollVelocity.x) < kInertiaMinimumVelocity && fabs(self.scrollVelocity.y) < kInertiaMinimumVelocity)) {
        [self stopScrolling];
        [self.host inputControllerDidFinishScrolling];
    }
}

- (void)scrollByPageFraction:(CGFloat)fraction horizontal:(BOOL)horizontal {
    UIScrollView *scrollView = [self.host inputControllerScrollView];
    if (scrollView == nil) {
        return;
    }
    [self stopScrolling];
    CGPoint offset = scrollView.contentOffset;
    CGFloat maxX = MAX(0.0, scrollView.contentSize.width - CGRectGetWidth(scrollView.bounds));
    CGFloat maxY = MAX(0.0, scrollView.contentSize.height - CGRectGetHeight(scrollView.bounds));
    CGPoint target = offset;
    if (horizontal) {
        target.x = MIN(MAX(offset.x + CGRectGetWidth(scrollView.bounds) * fraction, 0.0), maxX);
    } else {
        target.y = MIN(MAX(offset.y + CGRectGetHeight(scrollView.bounds) * fraction, 0.0), maxY);
    }
    if (CGPointEqualToPoint(target, offset)) {
        CGPoint delta = horizontal ? CGPointMake(CGRectGetWidth(scrollView.bounds) * fraction, 0.0)
                                   : CGPointMake(0.0, CGRectGetHeight(scrollView.bounds) * fraction);
        [self.host inputControllerScrollInnerContentAtPoint:self.cursorPoint delta:delta];
        return;
    }
    [scrollView setContentOffset:target animated:YES];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self.host inputControllerDidFinishScrolling];
    });
}

#pragma mark Touches

- (BOOL)handleTouchesBegan:(NSSet<UITouch *> *)touches {
    if (![self.host inputControllerPointerIsActive]) {
        return NO;
    }
    // A finger landing stops any coasting immediately.
    [self stopScrolling];
    self.hasLastTouchLocation = NO;
    return YES;
}

- (BOOL)handleTouchesMoved:(NSSet<UITouch *> *)touches {
    if (![self.host inputControllerPointerIsActive]) {
        return NO;
    }
    UITouch *touch = touches.anyObject;
    if (touch == nil) {
        return YES;
    }
    CGPoint location = [touch locationInView:self.rootView];
    CFTimeInterval now = touch.timestamp;
    if (!self.hasLastTouchLocation) {
        self.hasLastTouchLocation = YES;
        self.lastTouchLocation = location;
        self.lastTouchTimestamp = now;
        return YES;
    }
    CGPoint delta = CGPointMake((location.x - self.lastTouchLocation.x) * self.speedMultiplier,
                                (location.y - self.lastTouchLocation.y) * self.speedMultiplier);
    CFTimeInterval interval = now - self.lastTouchTimestamp;
    self.lastTouchLocation = location;
    self.lastTouchTimestamp = now;

    if (self.scrollModeEnabled) {
        // Content follows the finger.
        [self scrollBy:CGPointMake(-delta.x * kScrollGain, -delta.y * kScrollGain) trackVelocityWithInterval:interval];
        return YES;
    }

    CGRect bounds = self.rootView.bounds;
    CGPoint current = self.cursorView.center;
    CGPoint wanted = CGPointMake(current.x + delta.x, current.y + delta.y);
    CGPoint clamped = CGPointMake(MIN(MAX(wanted.x, 0.0), CGRectGetWidth(bounds)),
                                  MIN(MAX(wanted.y, 0.0), CGRectGetHeight(bounds)));
    self.cursorView.center = clamped;

    // Pushing the cursor past a screen edge scrolls the page by the amount it could not move.
    CGPoint overflow = CGPointMake(wanted.x - clamped.x, wanted.y - clamped.y);
    if (fabs(overflow.x) > 0.01 || fabs(overflow.y) > 0.01) {
        [self scrollBy:CGPointMake(overflow.x * kEdgeScrollGain, overflow.y * kEdgeScrollGain) trackVelocityWithInterval:interval];
    }
    [self.host inputControllerCursorDidMoveToPoint:clamped];
    return YES;
}

- (BOOL)handleTouchesEnded:(NSSet<UITouch *> *)touches {
    BOOL active = [self.host inputControllerPointerIsActive];
    self.hasLastTouchLocation = NO;
    if (!active) {
        return NO;
    }
    [self startInertiaIfNeeded];
    return YES;
}

#pragma mark Presses

- (void)cancelHolds {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(selectHoldTimerFired) object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(playPauseHoldTimerFired) object:nil];
    self.selectPressActive = NO;
    self.playPausePressActive = NO;
}

- (void)selectHoldTimerFired {
    if (!self.selectPressActive || ![self.host inputControllerPointerIsActive]) {
        return;
    }
    self.selectHoldFired = YES;
    self.cursorView.pressed = NO;
    [self.host inputControllerDidHoldAtPoint:self.cursorPoint];
}

- (void)playPauseHoldTimerFired {
    if (!self.playPausePressActive) {
        return;
    }
    self.playPauseHoldFired = YES;
    [self.host inputControllerOpenMenu];
}

- (BOOL)handlePressesBegan:(NSSet<UIPress *> *)presses {
    BOOL pointerActive = [self.host inputControllerPointerIsActive];
    BOOL consumed = NO;
    for (UIPress *press in presses) {
        switch (press.type) {
            case UIPressTypeSelect:
                if (pointerActive) {
                    self.selectPressActive = YES;
                    self.selectHoldFired = NO;
                    self.cursorView.pressed = YES;
                    [self stopScrolling];
                    [self performSelector:@selector(selectHoldTimerFired) withObject:nil afterDelay:kHoldDuration];
                    consumed = YES;
                }
                break;
            case UIPressTypePlayPause:
                self.playPausePressActive = YES;
                self.playPauseHoldFired = NO;
                if (pointerActive) {
                    [self performSelector:@selector(playPauseHoldTimerFired) withObject:nil afterDelay:kHoldDuration];
                }
                consumed = YES;
                break;
            case UIPressTypeMenu:
                self.menuPressClaimed = [self.host inputControllerCanHandleMenuPress];
                consumed = self.menuPressClaimed;
                break;
            case UIPressTypeUpArrow:
            case UIPressTypeDownArrow:
            case UIPressTypeLeftArrow:
            case UIPressTypeRightArrow:
                consumed = pointerActive;
                break;
            default:
                break;
        }
    }
    return consumed;
}

- (BOOL)handlePressesEnded:(NSSet<UIPress *> *)presses {
    BOOL pointerActive = [self.host inputControllerPointerIsActive];
    BOOL consumed = NO;
    for (UIPress *press in presses) {
        switch (press.type) {
            case UIPressTypeSelect: {
                [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(selectHoldTimerFired) object:nil];
                BOOL wasActive = self.selectPressActive;
                self.selectPressActive = NO;
                self.cursorView.pressed = NO;
                if (!pointerActive) {
                    break;
                }
                consumed = YES;
                self.lastDirectSelectTimestamp = CACurrentMediaTime();
                if (self.selectHoldFired) {
                    self.selectHoldFired = NO;
                } else if (wasActive) {
                    [self performPrimaryAction];
                }
                break;
            }
            case UIPressTypePlayPause: {
                [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(playPauseHoldTimerFired) object:nil];
                BOOL wasActive = self.playPausePressActive;
                self.playPausePressActive = NO;
                consumed = YES;
                if (self.playPauseHoldFired) {
                    self.playPauseHoldFired = NO;
                } else if (wasActive) {
                    if (pointerActive) {
                        self.scrollModeEnabled = !self.scrollModeEnabled;
                    } else {
                        [self.host inputControllerOpenMenu];
                    }
                }
                break;
            }
            case UIPressTypeMenu:
                if (self.menuPressClaimed) {
                    self.menuPressClaimed = NO;
                    consumed = YES;
                    [self.host inputControllerHandleMenuPress];
                }
                break;
            case UIPressTypeUpArrow:
            case UIPressTypeDownArrow:
                if (pointerActive) {
                    consumed = YES;
                    [self scrollByPageFraction:(press.type == UIPressTypeDownArrow ? 0.6 : -0.6) horizontal:NO];
                }
                break;
            case UIPressTypeLeftArrow:
            case UIPressTypeRightArrow:
                if (pointerActive) {
                    consumed = YES;
                    [self scrollByPageFraction:(press.type == UIPressTypeRightArrow ? 0.6 : -0.6) horizontal:YES];
                }
                break;
            default:
                break;
        }
    }
    return consumed;
}

- (BOOL)handlePressesCancelled:(NSSet<UIPress *> *)presses {
    BOOL consumed = self.selectPressActive || self.playPausePressActive || self.menuPressClaimed;
    [self cancelHolds];
    self.selectHoldFired = NO;
    self.playPauseHoldFired = NO;
    self.menuPressClaimed = NO;
    self.cursorView.pressed = NO;
    return consumed;
}

- (void)performPrimaryAction {
    if (self.scrollModeEnabled) {
        // A click while scrolling means "done scrolling".
        self.scrollModeEnabled = NO;
        return;
    }
    [self.host inputControllerDidClickAtPoint:self.cursorPoint];
}

- (void)handleGlobalSelectPressEnded {
    if (![self.host inputControllerPointerIsActive]) {
        return;
    }
    CFTimeInterval now = CACurrentMediaTime();
    // Already handled through the responder chain, or the pointer only just became active
    // (the same press dismissed a menu or opened a page from the start page).
    if ((now - self.lastDirectSelectTimestamp) < 0.2 || (now - self.pointerActivatedTimestamp) < 0.6 || self.selectPressActive) {
        return;
    }
    [self performPrimaryAction];
}

@end
