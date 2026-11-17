#import <UIKit/UIKit.h>
#import <objc/runtime.h>

NSString * const BrowserGlobalSelectPressEndedNotification = @"BrowserGlobalSelectPressEndedNotification";

// Depending on what tvOS thinks has focus, a click on the remote doesn't always reach the
// browser's view controller. Watching events at the application level catches every click;
// the input controller ignores the ones it has already handled.

static void (*BrowserOriginalSendEvent)(UIApplication *, SEL, UIEvent *);

static void BrowserSendEvent(UIApplication *application, SEL selector, UIEvent *event) {
    BrowserOriginalSendEvent(application, selector, event);
    if (event.type != UIEventTypePresses) {
        return;
    }
    NSSet<UIPress *> *presses = [event isKindOfClass:[UIPressesEvent class]] ? ((UIPressesEvent *)event).allPresses : nil;
    NSUInteger clickIndex = [presses.allObjects indexOfObjectPassingTest:^BOOL(UIPress *press, NSUInteger index, BOOL *stop) {
        return press.type == UIPressTypeSelect && press.phase == UIPressPhaseEnded;
    }];
    if (clickIndex != NSNotFound) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:BrowserGlobalSelectPressEndedNotification object:nil];
        });
    }
}

__attribute__((constructor))
static void BrowserObserveSelectPresses(void) {
    Method sendEvent = class_getInstanceMethod([UIApplication class], @selector(sendEvent:));
    BrowserOriginalSendEvent = (void (*)(UIApplication *, SEL, UIEvent *))method_setImplementation(sendEvent, (IMP)BrowserSendEvent);
}
