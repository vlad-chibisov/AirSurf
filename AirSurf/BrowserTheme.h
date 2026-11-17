#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Shared look: materials, colours, type, motion.
@interface BrowserTheme : NSObject

/// YES on hardware where Liquid Glass is not worth its cost (Apple TV HD and the first
/// Apple TV 4K) or when Reduce Transparency is on. Chrome then uses a plain dark blur.
+ (BOOL)usesLightweightMaterials;
/// Floating chrome: toolbar, HUD.
+ (UIVisualEffect *)chromeEffect;
/// Large surfaces: side panel.
+ (UIVisualEffect *)panelEffect;

+ (UIColor *)accentColor;
+ (UIColor *)primaryTextColor;
+ (UIColor *)secondaryTextColor;
/// Stable colour for a site tile, derived from its host name.
+ (UIColor *)tileColorForString:(NSString *)string;

+ (UIImage *)symbolNamed:(NSString *)name pointSize:(CGFloat)pointSize weight:(UIImageSymbolWeight)weight;

/// Critically damped spring: the default for everything that moves.
+ (void)animate:(void (^)(void))animations;
+ (void)animate:(void (^)(void))animations completion:(void (^ _Nullable)(void))completion;
/// Slightly quicker spring for small state changes (hover, press).
+ (void)animateQuick:(void (^)(void))animations;

@end

NS_ASSUME_NONNULL_END
