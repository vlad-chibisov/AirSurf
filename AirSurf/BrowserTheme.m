#import "BrowserTheme.h"

#import <sys/utsname.h>

@implementation BrowserTheme

+ (NSString *)hardwareModel {
    NSString *simulatedModel = NSProcessInfo.processInfo.environment[@"SIMULATOR_MODEL_IDENTIFIER"];
    if (simulatedModel.length > 0) {
        return simulatedModel;
    }
    struct utsname systemInfo;
    uname(&systemInfo);
    return [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding] ?: @"";
}

+ (BOOL)usesLightweightMaterials {
    static BOOL olderHardware;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *override = NSProcessInfo.processInfo.environment[@"BROWSER_MATERIALS"];
        if ([override isEqualToString:@"light"]) {
            olderHardware = YES;
        } else if ([override isEqualToString:@"glass"]) {
            olderHardware = NO;
        } else {
            // AppleTV5,3 = Apple TV HD (A8), AppleTV6,2 = Apple TV 4K 1st generation (A10X).
            olderHardware = [@[@"AppleTV5,3", @"AppleTV6,2"] containsObject:[self hardwareModel]];
        }
    });
    return olderHardware || UIAccessibilityIsReduceTransparencyEnabled();
}

+ (UIVisualEffect *)chromeEffect {
    if ([self usesLightweightMaterials]) {
        // Extra Dark stays dark over white pages; plain Dark turns grey there.
        return [UIBlurEffect effectWithStyle:UIBlurEffectStyleExtraDark];
    }
    UIGlassEffect *glass = [UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular];
    glass.tintColor = [UIColor colorWithWhite:0.0 alpha:0.42];
    return glass;
}

+ (UIVisualEffect *)panelEffect {
    if ([self usesLightweightMaterials]) {
        return [UIBlurEffect effectWithStyle:UIBlurEffectStyleExtraDark];
    }
    UIGlassEffect *glass = [UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular];
    glass.tintColor = [UIColor colorWithWhite:0.0 alpha:0.55];
    return glass;
}

+ (UIColor *)accentColor {
    return [UIColor colorWithRed:0.04 green:0.52 blue:1.0 alpha:1.0];
}

+ (UIColor *)primaryTextColor {
    return [UIColor colorWithWhite:1.0 alpha:0.96];
}

+ (UIColor *)secondaryTextColor {
    return [UIColor colorWithWhite:1.0 alpha:0.6];
}

+ (UIColor *)tileColorForString:(NSString *)string {
    NSUInteger hash = 5381;
    for (NSUInteger index = 0; index < string.length; index += 1) {
        hash = ((hash << 5) + hash) ^ [string characterAtIndex:index];
    }
    CGFloat hue = (CGFloat)(hash % 360) / 360.0;
    return [UIColor colorWithHue:hue saturation:0.55 brightness:0.62 alpha:1.0];
}

+ (UIImage *)symbolNamed:(NSString *)name pointSize:(CGFloat)pointSize weight:(UIImageSymbolWeight)weight {
    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:pointSize weight:weight];
    UIImage *image = [UIImage systemImageNamed:name withConfiguration:configuration];
    if (image == nil) {
        image = [UIImage systemImageNamed:@"questionmark.circle" withConfiguration:configuration];
    }
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

+ (void)animateWithDuration:(NSTimeInterval)duration animations:(void (^)(void))animations completion:(void (^)(void))completion {
    if (UIAccessibilityIsReduceMotionEnabled()) {
        // Reduced motion keeps the state change but drops the travel.
        [UIView animateWithDuration:0.2
                              delay:0.0
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseOut
                         animations:animations
                         completion:^(__unused BOOL finished) {
            if (completion != nil) {
                completion();
            }
        }];
        return;
    }
    [UIView animateWithSpringDuration:duration
                               bounce:0.0
                initialSpringVelocity:0.0
                                delay:0.0
                              options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                           animations:animations
                           completion:^(__unused BOOL finished) {
        if (completion != nil) {
            completion();
        }
    }];
}

+ (void)animate:(void (^)(void))animations {
    [self animateWithDuration:0.4 animations:animations completion:nil];
}

+ (void)animate:(void (^)(void))animations completion:(void (^)(void))completion {
    [self animateWithDuration:0.4 animations:animations completion:completion];
}

+ (void)animateQuick:(void (^)(void))animations {
    [self animateWithDuration:0.22 animations:animations completion:nil];
}

@end
