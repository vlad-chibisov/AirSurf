#import "BrowserTabViewModel.h"

static NSString * const kUntitledTabTitle = @"New Tab";
// Larger states (long histories with form data) aren't worth the space in the saved session.
static NSUInteger const kMaximumSavedInteractionStateBytes = 1 << 20;

static id BrowserSessionValue(NSDictionary *session, NSString *key, Class expectedClass) {
    id value = session[key];
    return [value isKindOfClass:expectedClass] ? value : nil;
}

@implementation BrowserTabViewModel {
    BOOL _storedSnapshotLookedUp;
}

@synthesize snapshotImage = _snapshotImage;

- (instancetype)init {
    return [self initWithIdentifier:[NSUUID UUID].UUIDString];
}

- (instancetype)initWithIdentifier:(NSString *)identifier {
    if ((self = [super init])) {
        _identifier = [identifier copy];
        _title = kUntitledTabTitle;
        _URLString = @"";
    }
    return self;
}

- (instancetype)initWithSessionRepresentation:(NSDictionary *)session {
    NSString *identifier = BrowserSessionValue(session, @"identifier", [NSString class]);
    self = [self initWithIdentifier:identifier.length > 0 ? identifier : [NSUUID UUID].UUIDString];
    if (self) {
        NSString *title = BrowserSessionValue(session, @"title", [NSString class]);
        _title = title.length > 0 ? [title copy] : kUntitledTabTitle;
        _URLString = [BrowserSessionValue(session, @"URLString", [NSString class]) copy] ?: @"";
        _interactionState = [BrowserSessionValue(session, @"interactionState", [NSData class]) copy];
        _showsStartPage = [BrowserSessionValue(session, @"showsStartPage", [NSNumber class]) boolValue];
    }
    return self;
}

- (NSDictionary *)sessionRepresentation {
    NSMutableDictionary *session = [@{
        @"identifier": self.identifier,
        @"title": self.title ?: kUntitledTabTitle,
        @"URLString": self.URLString ?: @"",
        @"showsStartPage": @(self.showsStartPage),
    } mutableCopy];
    NSUInteger stateSize = self.interactionState.length;
    if (stateSize > 0 && stateSize < kMaximumSavedInteractionStateBytes) {
        session[@"interactionState"] = self.interactionState;
    }
    return session;
}

#pragma mark - Thumbnail

- (NSURL *)snapshotFileURL {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *folder = [[fileManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject
                     URLByAppendingPathComponent:@"TabSnapshots" isDirectory:YES];
    [fileManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:NULL];
    return [folder URLByAppendingPathComponent:[self.identifier stringByAppendingString:@".jpg"]];
}

- (UIImage *)snapshotImage {
    if (_snapshotImage == nil && !_storedSnapshotLookedUp) {
        _storedSnapshotLookedUp = YES;
        _snapshotImage = [UIImage imageWithContentsOfFile:self.snapshotFileURL.path];
    }
    return _snapshotImage;
}

- (void)setSnapshotImage:(UIImage *)image {
    _snapshotImage = image;
    _storedSnapshotLookedUp = YES;
    if (image == nil) {
        return;
    }
    NSURL *destination = self.snapshotFileURL;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [UIImageJPEGRepresentation(image, 0.6) writeToURL:destination atomically:YES];
    });
}

- (void)removeStoredSnapshot {
    [[NSFileManager defaultManager] removeItemAtURL:self.snapshotFileURL error:NULL];
}

@end
