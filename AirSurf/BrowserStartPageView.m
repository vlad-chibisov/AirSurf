#import "BrowserStartPageView.h"

#import "BrowserLibraryStore.h"
#import "BrowserTheme.h"

static NSString * const kTileCellIdentifier = @"BrowserSiteTileCell";
static NSString * const kHeaderIdentifier = @"BrowserStartPageHeader";
static CGFloat const kTileArtworkHeight = 176.0;
static CGFloat const kTileHeight = 262.0;
static NSUInteger const kTilesPerRow = 5;

#pragma mark - Site icons

/// Fetches a site's own touch icon straight from the site. Nothing is sent to a third party.
@interface BrowserSiteIconLoader : NSObject

+ (instancetype)sharedLoader;
- (void)loadIconForHost:(NSString *)host scheme:(NSString *)scheme completion:(void (^)(UIImage * _Nullable image))completion;

@end

@implementation BrowserSiteIconLoader {
    NSCache<NSString *, id> *_cache;
    NSURLSession *_session;
}

+ (instancetype)sharedLoader {
    static BrowserSiteIconLoader *loader;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        loader = [BrowserSiteIconLoader new];
    });
    return loader;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cache = [NSCache new];
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        configuration.timeoutIntervalForRequest = 8.0;
        configuration.HTTPCookieAcceptPolicy = NSHTTPCookieAcceptPolicyNever;
        _session = [NSURLSession sessionWithConfiguration:configuration];
    }
    return self;
}

- (NSURL *)cacheFileURLForHost:(NSString *)host {
    NSURL *caches = [[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *directory = [caches URLByAppendingPathComponent:@"SiteIcons" isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *safeName = [[host componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/:\\"]] componentsJoinedByString:@"_"];
    return [directory URLByAppendingPathComponent:[safeName stringByAppendingPathExtension:@"png"]];
}

- (void)loadIconForHost:(NSString *)host scheme:(NSString *)scheme completion:(void (^)(UIImage *))completion {
    if (host.length == 0) {
        completion(nil);
        return;
    }
    id cached = [_cache objectForKey:host];
    if (cached != nil) {
        completion([cached isKindOfClass:[UIImage class]] ? cached : nil);
        return;
    }
    NSURL *fileURL = [self cacheFileURLForHost:host];
    UIImage *stored = [UIImage imageWithContentsOfFile:fileURL.path];
    if (stored != nil) {
        [_cache setObject:stored forKey:host];
        completion(stored);
        return;
    }
    NSString *base = [NSString stringWithFormat:@"%@://%@", scheme.length > 0 ? scheme : @"https", host];
    NSArray<NSString *> *paths = @[@"/apple-touch-icon.png", @"/apple-touch-icon-precomposed.png", @"/favicon.ico"];
    [self fetchIconFromBase:base paths:paths index:0 host:host fileURL:fileURL completion:completion];
}

- (void)fetchIconFromBase:(NSString *)base
                    paths:(NSArray<NSString *> *)paths
                    index:(NSUInteger)index
                     host:(NSString *)host
                  fileURL:(NSURL *)fileURL
               completion:(void (^)(UIImage *))completion {
    if (index >= paths.count) {
        [_cache setObject:[NSNull null] forKey:host];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil);
        });
        return;
    }
    NSURL *URL = [NSURL URLWithString:[base stringByAppendingString:paths[index]]];
    NSURLSessionDataTask *task = [_session dataTaskWithURL:URL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger statusCode = [response isKindOfClass:[NSHTTPURLResponse class]] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        UIImage *image = (error == nil && statusCode == 200 && data.length > 0) ? [UIImage imageWithData:data] : nil;
        // Tiny favicons look worse than the monogram tile, so they are skipped.
        if (image == nil || image.size.width * image.scale < 48.0) {
            [self fetchIconFromBase:base paths:paths index:index + 1 host:host fileURL:fileURL completion:completion];
            return;
        }
        [self->_cache setObject:image forKey:host];
        [UIImagePNGRepresentation(image) writeToURL:fileURL atomically:YES];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(image);
        });
    }];
    [task resume];
}

@end

#pragma mark - Tile

@interface BrowserSiteTileCell : UICollectionViewCell

@property (nonatomic) UIView *artworkView;
@property (nonatomic) CAGradientLayer *gradientLayer;
@property (nonatomic) UILabel *monogramLabel;
@property (nonatomic) UIImageView *iconView;
@property (nonatomic) UILabel *titleLabel;
@property (nonatomic) UILabel *hostLabel;
@property (nonatomic, copy) NSString *representedHost;

@end

@implementation BrowserSiteTileCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.clipsToBounds = NO;
        self.contentView.clipsToBounds = NO;

        _artworkView = [[UIView alloc] initWithFrame:CGRectZero];
        _artworkView.layer.cornerRadius = 28.0;
        _artworkView.layer.cornerCurve = kCACornerCurveContinuous;
        _artworkView.layer.shadowColor = UIColor.blackColor.CGColor;
        _artworkView.layer.shadowOffset = CGSizeMake(0.0, 18.0);
        _artworkView.layer.shadowRadius = 26.0;
        _artworkView.layer.shadowOpacity = 0.0;
        [self.contentView addSubview:_artworkView];

        _gradientLayer = [CAGradientLayer layer];
        _gradientLayer.cornerRadius = 28.0;
        _gradientLayer.cornerCurve = kCACornerCurveContinuous;
        _gradientLayer.startPoint = CGPointMake(0.0, 0.0);
        _gradientLayer.endPoint = CGPointMake(1.0, 1.0);
        [_artworkView.layer addSublayer:_gradientLayer];

        _monogramLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _monogramLabel.font = [UIFont systemFontOfSize:78.0 weight:UIFontWeightBold];
        _monogramLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.95];
        _monogramLabel.textAlignment = NSTextAlignmentCenter;
        [_artworkView addSubview:_monogramLabel];

        _iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.layer.cornerRadius = 22.0;
        _iconView.layer.cornerCurve = kCACornerCurveContinuous;
        _iconView.clipsToBounds = YES;
        _iconView.hidden = YES;
        [_artworkView addSubview:_iconView];

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.font = [UIFont systemFontOfSize:27.0 weight:UIFontWeightSemibold];
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:_titleLabel];

        _hostLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _hostLabel.font = [UIFont systemFontOfSize:22.0 weight:UIFontWeightRegular];
        _hostLabel.textAlignment = NSTextAlignmentCenter;
        _hostLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [self.contentView addSubview:_hostLabel];

        [self applyFocusAppearance];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    CGAffineTransform transform = self.artworkView.transform;
    self.artworkView.transform = CGAffineTransformIdentity;
    self.artworkView.frame = CGRectMake(0.0, 0.0, width, kTileArtworkHeight);
    self.artworkView.transform = transform;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.gradientLayer.frame = self.artworkView.bounds;
    [CATransaction commit];
    self.monogramLabel.frame = self.artworkView.bounds;
    self.iconView.bounds = CGRectMake(0.0, 0.0, 104.0, 104.0);
    self.iconView.center = CGPointMake(width / 2.0, kTileArtworkHeight / 2.0);
    self.titleLabel.frame = CGRectMake(0.0, kTileArtworkHeight + 20.0, width, 34.0);
    self.hostLabel.frame = CGRectMake(0.0, kTileArtworkHeight + 54.0, width, 28.0);
}

- (void)configureWithEntry:(BrowserLibraryEntry *)entry {
    NSString *host = entry.displayHost;
    self.representedHost = host;
    self.titleLabel.text = entry.displayTitle;
    self.hostLabel.text = [entry.displayTitle isEqualToString:host] ? @"" : host;
    self.accessibilityLabel = entry.displayTitle;

    UIColor *base = [BrowserTheme tileColorForString:host];
    CGFloat hue = 0.0, saturation = 0.0, brightness = 0.0, alpha = 0.0;
    [base getHue:&hue saturation:&saturation brightness:&brightness alpha:&alpha];
    UIColor *deep = [UIColor colorWithHue:fmod(hue + 0.06, 1.0) saturation:MIN(1.0, saturation + 0.15) brightness:brightness * 0.55 alpha:1.0];
    self.gradientLayer.colors = @[(id)base.CGColor, (id)deep.CGColor];

    NSString *monogramSource = entry.displayTitle.length > 0 ? entry.displayTitle : host;
    self.monogramLabel.text = monogramSource.length > 0 ? [[monogramSource substringToIndex:[monogramSource rangeOfComposedCharacterSequenceAtIndex:0].length] uppercaseString] : @"?";
    self.monogramLabel.hidden = NO;
    self.iconView.hidden = YES;
    self.iconView.image = nil;

    NSURL *URL = [NSURL URLWithString:entry.URLString];
    __weak typeof(self) weakSelf = self;
    [[BrowserSiteIconLoader sharedLoader] loadIconForHost:URL.host ?: @"" scheme:URL.scheme ?: @"https" completion:^(UIImage *image) {
        if (image == nil || ![weakSelf.representedHost isEqualToString:host]) {
            return;
        }
        weakSelf.iconView.image = image;
        weakSelf.iconView.hidden = NO;
        weakSelf.monogramLabel.hidden = YES;
    }];
}

- (void)applyFocusAppearance {
    BOOL focused = self.focused;
    self.artworkView.transform = focused ? CGAffineTransformMakeScale(1.1, 1.1) : CGAffineTransformIdentity;
    self.artworkView.layer.shadowOpacity = focused ? 0.55 : 0.0;
    self.titleLabel.textColor = focused ? UIColor.whiteColor : [UIColor colorWithWhite:1.0 alpha:0.78];
    self.hostLabel.textColor = [UIColor colorWithWhite:1.0 alpha:focused ? 0.7 : 0.45];
    CGAffineTransform labelShift = focused ? CGAffineTransformMakeTranslation(0.0, 10.0) : CGAffineTransformIdentity;
    self.titleLabel.transform = labelShift;
    self.hostLabel.transform = labelShift;
}

- (void)didUpdateFocusInContext:(UIFocusUpdateContext *)context withAnimationCoordinator:(UIFocusAnimationCoordinator *)coordinator {
    [super didUpdateFocusInContext:context withAnimationCoordinator:coordinator];
    [coordinator addCoordinatedAnimations:^{
        [self applyFocusAppearance];
    } completion:nil];
}

@end

#pragma mark - Header

@interface BrowserStartPageHeaderView : UICollectionReusableView

@property (nonatomic) UILabel *label;

@end

@implementation BrowserStartPageHeaderView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _label = [[UILabel alloc] initWithFrame:self.bounds];
        _label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _label.font = [UIFont systemFontOfSize:36.0 weight:UIFontWeightBold];
        _label.textColor = [BrowserTheme primaryTextColor];
        [self addSubview:_label];
    }
    return self;
}

@end

#pragma mark - Start page

@interface BrowserStartPageView () <UICollectionViewDataSource, UICollectionViewDelegate>

@property (nonatomic) UICollectionView *collectionView;
@property (nonatomic) UILabel *emptyLabel;
@property (nonatomic, copy) NSArray<BrowserLibraryEntry *> *favorites;
@property (nonatomic, copy) NSArray<BrowserLibraryEntry *> *recents;
@property (nonatomic, copy) NSArray<NSDictionary *> *sections;

@end

@implementation BrowserStartPageView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithRed:0.055 green:0.06 blue:0.075 alpha:1.0];
        _favorites = @[];
        _recents = @[];
        _sections = @[];

        _collectionView = [[UICollectionView alloc] initWithFrame:self.bounds collectionViewLayout:[self makeLayout]];
        _collectionView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _collectionView.backgroundColor = UIColor.clearColor;
        _collectionView.dataSource = self;
        _collectionView.delegate = self;
        _collectionView.clipsToBounds = NO;
        _collectionView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
        _collectionView.remembersLastFocusedIndexPath = YES;
        [_collectionView registerClass:[BrowserSiteTileCell class] forCellWithReuseIdentifier:kTileCellIdentifier];
        [_collectionView registerClass:[BrowserStartPageHeaderView class]
            forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
                   withReuseIdentifier:kHeaderIdentifier];
        [self addSubview:_collectionView];

        _emptyLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _emptyLabel.numberOfLines = 0;
        _emptyLabel.textAlignment = NSTextAlignmentCenter;
        _emptyLabel.font = [UIFont systemFontOfSize:31.0 weight:UIFontWeightRegular];
        _emptyLabel.textColor = [BrowserTheme secondaryTextColor];
        _emptyLabel.text = @"Sites you add to Favorites appear here.\nOpen a page and choose the star in the toolbar.";
        _emptyLabel.hidden = YES;
        [self addSubview:_emptyLabel];

        UILongPressGestureRecognizer *holdRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleHold:)];
        holdRecognizer.allowedPressTypes = @[@(UIPressTypeSelect)];
        holdRecognizer.minimumPressDuration = 0.55;
        [_collectionView addGestureRecognizer:holdRecognizer];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadContent) name:BrowserLibraryDidChangeNotification object:nil];
        [self reloadContent];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (UICollectionViewLayout *)makeLayout {
    NSCollectionLayoutSize *itemSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0 / kTilesPerRow]
                                                                      heightDimension:[NSCollectionLayoutDimension fractionalHeightDimension:1.0]];
    NSCollectionLayoutItem *item = [NSCollectionLayoutItem itemWithLayoutSize:itemSize];
    item.contentInsets = NSDirectionalEdgeInsetsMake(0.0, 20.0, 0.0, 20.0);
    NSCollectionLayoutSize *groupSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                                                       heightDimension:[NSCollectionLayoutDimension absoluteDimension:kTileHeight]];
    NSCollectionLayoutGroup *group = [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:groupSize subitems:@[item]];
    NSCollectionLayoutSection *section = [NSCollectionLayoutSection sectionWithGroup:group];
    section.interGroupSpacing = 36.0;
    section.contentInsets = NSDirectionalEdgeInsetsMake(26.0, 60.0, 64.0, 60.0);
    NSCollectionLayoutSize *headerSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                                                        heightDimension:[NSCollectionLayoutDimension absoluteDimension:48.0]];
    NSCollectionLayoutBoundarySupplementaryItem *header = [NSCollectionLayoutBoundarySupplementaryItem boundarySupplementaryItemWithLayoutSize:headerSize
                                                                                                                                     elementKind:UICollectionElementKindSectionHeader
                                                                                                                                       alignment:NSRectAlignmentTop];
    header.contentInsets = NSDirectionalEdgeInsetsMake(0.0, 20.0, 0.0, 20.0);
    section.boundarySupplementaryItems = @[header];
    return [[UICollectionViewCompositionalLayout alloc] initWithSection:section];
}

- (void)setTopInset:(CGFloat)topInset {
    _topInset = topInset;
    self.collectionView.contentInset = UIEdgeInsetsMake(topInset + 44.0, 0.0, 60.0, 0.0);
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.emptyLabel.frame = CGRectMake(200.0, self.topInset, CGRectGetWidth(self.bounds) - 400.0, CGRectGetHeight(self.bounds) - self.topInset - 80.0);
}

- (void)reloadContent {
    BrowserLibraryStore *store = [BrowserLibraryStore sharedStore];
    self.favorites = store.favorites;
    self.recents = [store recentSitesWithLimit:kTilesPerRow * 2];
    NSMutableArray<NSDictionary *> *sections = [NSMutableArray array];
    if (self.favorites.count > 0) {
        [sections addObject:@{ @"title": @"Favorites", @"entries": self.favorites, @"favorite": @YES }];
    }
    if (self.recents.count > 0) {
        [sections addObject:@{ @"title": @"Recently Visited", @"entries": self.recents, @"favorite": @NO }];
    }
    self.sections = sections;
    self.emptyLabel.hidden = sections.count > 0;
    [self.collectionView reloadData];
}

- (NSArray<BrowserLibraryEntry *> *)entriesInSection:(NSInteger)section {
    return self.sections[(NSUInteger)section][@"entries"];
}

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return (NSInteger)self.sections.count;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return (NSInteger)[self entriesInSection:section].count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    BrowserSiteTileCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:kTileCellIdentifier forIndexPath:indexPath];
    [cell configureWithEntry:[self entriesInSection:indexPath.section][(NSUInteger)indexPath.item]];
    return cell;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath {
    BrowserStartPageHeaderView *header = [collectionView dequeueReusableSupplementaryViewOfKind:kind withReuseIdentifier:kHeaderIdentifier forIndexPath:indexPath];
    header.label.text = self.sections[(NSUInteger)indexPath.section][@"title"];
    return header;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [self.delegate startPageView:self didSelectEntry:[self entriesInSection:indexPath.section][(NSUInteger)indexPath.item]];
}

- (void)handleHold:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateBegan) {
        return;
    }
    UIView *focusedView = (UIView *)[UIFocusSystem focusSystemForEnvironment:self].focusedItem;
    if (![focusedView isKindOfClass:[UICollectionViewCell class]]) {
        return;
    }
    NSIndexPath *indexPath = [self.collectionView indexPathForCell:(UICollectionViewCell *)focusedView];
    if (indexPath == nil) {
        return;
    }
    BOOL isFavorite = [self.sections[(NSUInteger)indexPath.section][@"favorite"] boolValue];
    [self.delegate startPageView:self didRequestActionsForEntry:[self entriesInSection:indexPath.section][(NSUInteger)indexPath.item] isFavorite:isFavorite];
}

- (NSArray<id<UIFocusEnvironment>> *)preferredFocusEnvironments {
    return @[self.collectionView];
}

@end
