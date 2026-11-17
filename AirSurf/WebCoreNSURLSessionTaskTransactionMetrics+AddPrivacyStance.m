#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// WebKit's media loader asks its WebCoreNSURLSessionTaskTransactionMetrics objects for a
// privacy stance, and some tvOS builds don't implement that selector, so playback would
// crash with "unrecognized selector". Answer "unknown" (0) wherever it's missing.
//
// The class lives in WebCore, which is only in the process once BrowserWebView has loaded
// WebKit, so this is called from there rather than at launch.

static NSInteger BrowserUnknownPrivacyStance(id receiver, SEL selector) {
    return 0;
}

void BrowserInstallPrivacyStanceFallback(void) {
    Class metrics = objc_getClass("WebCoreNSURLSessionTaskTransactionMetrics");
    if (metrics == Nil) {
        return;
    }
    for (NSString *name in @[@"privacyStance", @"_privacyStance"]) {
        // class_addMethod leaves an existing implementation alone.
        class_addMethod(metrics, NSSelectorFromString(name), (IMP)BrowserUnknownPrivacyStance, "q@:");
    }
}
