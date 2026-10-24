// Library redesign: a picture of the person's own on a folder, in place of Spotify's gray folder tile.
//
// Spotify draws a folder in Your Library as a gray square with a folder glyph, and gives it no artwork of its
// own to replace. Here each folder can be given a photo: Appearance > Folder pictures lists the folders the
// library has shown, a tap picks a photo (the system's picker, which asks for no permission), and the photo is
// cropped square, kept in Application Support and laid over the row's thumbnail while that row is a folder.
//
// A folder's row is recognised by what it says, since nothing recorded in this repo names its thumbnail: it
// reads its name, then how many it holds ("22 playlists"), where a playlist, album or show reads its kind
// with a bullet ("Playlist • gio"). Folders are told apart by name; two folders with one name share a picture.
// The thumbnail is the row's Artwork.Row.Library if it has one, else the first square of about 64pt at its
// leading edge. If a row is never taken for a folder, the page says so (no folders listed) and the debug row
// copies what the first rows the library drew contain, which is how to find what the folder's row is made of.
//
// Threading: main thread only (the picture is cut on the picker's queue and stored back on main).
#import <PhotosUI/PhotosUI.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Library.h"

// Folder name -> file name, and the names the library has shown, in the order it showed them.
static NSString *const kPicturesKey = @"spotifyglass.redesign.library.folderPictures";
static NSString *const kSeenKey = @"spotifyglass.redesign.library.folderNames";

static char kThumbKey, kOverlayKey, kDelegateKey;

#pragma mark - what is stored

static NSDictionary<NSString *, NSString *> *stored(void) {
    return [NSUserDefaults.standardUserDefaults dictionaryForKey:kPicturesKey] ?: @{};
}

static NSURL *directoryURL(void) {
    NSURL *base = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    return [base URLByAppendingPathComponent:@"spotifyglass-folder-pictures" isDirectory:YES];
}

static NSCache<NSString *, UIImage *> *cache(void) {
    static NSCache *images;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ images = [NSCache new]; });
    return images;
}

static UIImage *pictureFor(NSString *name) {
    NSString *file = stored()[name];
    if (!file) return nil;
    UIImage *image = [cache() objectForKey:file];
    if (!image) {
        image = [UIImage imageWithContentsOfFile:[directoryURL() URLByAppendingPathComponent:file].path];
        if (image) [cache() setObject:image forKey:file];
    }
    return image;
}

static void remember(NSString *name) {
    NSArray<NSString *> *seen = [NSUserDefaults.standardUserDefaults stringArrayForKey:kSeenKey] ?: @[];
    if ([seen containsObject:name]) return;
    [NSUserDefaults.standardUserDefaults setObject:[seen arrayByAddingObject:name] forKey:kSeenKey];
}

static void save(NSString *name, NSData *data) {
    NSURL *directory = directoryURL();
    [NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *file = [NSString stringWithFormat:@"%@.jpg", NSUUID.UUID.UUIDString];
    if (![data writeToURL:[directory URLByAppendingPathComponent:file] atomically:YES]) return;
    NSMutableDictionary<NSString *, NSString *> *map = [stored() mutableCopy];
    NSString *old = map[name];
    if (old) [NSFileManager.defaultManager removeItemAtURL:[directory URLByAppendingPathComponent:old] error:nil];
    map[name] = file;
    [NSUserDefaults.standardUserDefaults setObject:map forKey:kPicturesKey];
}

static void removePicture(NSString *name) {
    NSMutableDictionary<NSString *, NSString *> *map = [stored() mutableCopy];
    NSString *file = map[name];
    if (!file) return;
    [NSFileManager.defaultManager removeItemAtURL:[directoryURL() URLByAppendingPathComponent:file] error:nil];
    [map removeObjectForKey:name];
    [NSUserDefaults.standardUserDefaults setObject:map forKey:kPicturesKey];
}

// The photo cut to a 256pt square from its middle: a thumbnail is 64pt, so this is sharp at 3x with room over.
static NSData *squareJPEG(UIImage *image) {
    const CGFloat side = 256;
    if (image.size.width < 1 || image.size.height < 1) return nil;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = 1;
    format.opaque = YES;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side) format:format];
    return [renderer JPEGDataWithCompressionQuality:0.9 actions:^(UIGraphicsImageRendererContext *context) {
        CGFloat scale = MAX(side / image.size.width, side / image.size.height);
        CGSize drawn = CGSizeMake(image.size.width * scale, image.size.height * scale);
        [image drawInRect:CGRectMake((side - drawn.width) / 2, (side - drawn.height) / 2, drawn.width, drawn.height)];
    }];
}

#pragma mark - reading a row

// Every label under the row, top to bottom and then left to right: what the row says.
static NSArray<NSString *> *linesOf(UIView *cell) {
    NSMutableArray<NSDictionary *> *found = [NSMutableArray array];
    SGForEachView(cell, ^(UIView *view) {
        if (![view isKindOfClass:UILabel.class]) return;
        NSString *text = ((UILabel *)view).text;
        if (!text.length) return;
        CGRect frame = SGFrameIn(view, cell);
        [found addObject:@{@"text": text, @"y": @(frame.origin.y), @"x": @(frame.origin.x)}];
    });
    [found sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSComparisonResult byY = [(NSNumber *)a[@"y"] compare:(NSNumber *)b[@"y"]];
        return byY != NSOrderedSame ? byY : [(NSNumber *)a[@"x"] compare:(NSNumber *)b[@"x"]];
    }];
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (NSDictionary *entry in found) [lines addObject:entry[@"text"]];
    return lines;
}

// A folder's name, when the row is a folder's: the name, then a count with no bullet in it.
static NSString *folderNameIn(NSArray<NSString *> *lines) {
    if (lines.count < 2) return nil;
    NSString *kind = lines[1];
    if ([kind containsString:@"•"]) return nil;
    return [kind rangeOfString:@"^[0-9]+ " options:NSRegularExpressionSearch].location == NSNotFound ? nil : lines[0];
}

// The row's thumbnail: Spotify's own for a playlist, album or show, else the first square of about 64pt at the
// leading edge, which is what a folder's tile is if it has no identifier of its own.
static UIView *thumbOf(UIView *cell) {
    UIView *thumb = SGRFindByIdentifier(cell, @"Artwork.Row.Library", &kThumbKey);
    if (thumb) return thumb;
    __block UIView *found = nil;
    SGForEachView(cell, ^(UIView *view) {
        if (found || view == cell) return;
        CGRect frame = SGFrameIn(view, cell);
        if (frame.size.width >= 56 && frame.size.width <= 72 && fabs(frame.size.width - frame.size.height) < 2 && frame.origin.x < 40) found = view;
    });
    return found;
}

#pragma mark - what the first rows contain

static void dumpView(UIView *view, UIView *root, int depth, NSMutableString *out) {
    if (depth > 8 || out.length > 5000) return;
    NSString *text = [view isKindOfClass:UILabel.class] ? ((UILabel *)view).text : nil;
    [out appendFormat:@"%*s%@ id=%@ %@%@\n", depth * 2, "", NSStringFromClass(view.class), view.accessibilityIdentifier ?: @"-",
     NSStringFromCGRect(SGFrameIn(view, root)), text ? [NSString stringWithFormat:@" \"%@\"", text] : @""];
    for (UIView *sub in view.subviews) dumpView(sub, root, depth + 1, out);
}

// The first dozen rows the library drew, each once, as their view trees; the page's debug row copies them.
static NSMutableArray<NSString *> *dumps(void) {
    static NSMutableArray *rows;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ rows = [NSMutableArray array]; });
    return rows;
}

static NSMutableSet<NSString *> *dumpedTitles(void) {
    static NSMutableSet *titles;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ titles = [NSMutableSet set]; });
    return titles;
}

static void record(UIView *cell, NSArray<NSString *> *lines) {
    NSString *title = lines.firstObject;
    if (!title || dumps().count >= 12 || [dumpedTitles() containsObject:title]) return;
    [dumpedTitles() addObject:title];
    NSMutableString *out = [NSMutableString stringWithFormat:@"--- row %@, says %@\n", NSStringFromCGSize(cell.bounds.size), lines];
    dumpView(cell, cell, 0, out);
    [dumps() addObject:out];
}

#pragma mark - the library's rows

// Called as each row of the list lays out (LibraryRows.x). A folder with a picture gets it over its thumbnail, any
// other row, including one that was a folder when it last held this cell, loses it.
void SGRFolderPicturesStyle(UIView *cell) {
    UIImageView *overlay = objc_getAssociatedObject(cell, &kOverlayKey);
    CGSize size = cell.bounds.size;
    NSArray<NSString *> *lines = (size.width > 300 && size.height <= 120) ? linesOf(cell) : nil;
    NSString *name = folderNameIn(lines);
    if (lines.count) record(cell, lines);
    if (name) remember(name);
    UIImage *picture = name ? pictureFor(name) : nil;
    UIView *thumb = picture ? thumbOf(cell) : nil;
    if (!picture || !thumb) {
        if (overlay.superview) [overlay removeFromSuperview];
        return;
    }
    if (!overlay) {
        overlay = [UIImageView new];
        overlay.contentMode = UIViewContentModeScaleAspectFill;
        overlay.clipsToBounds = YES;
        overlay.isAccessibilityElement = NO;
        overlay.layer.cornerRadius = SGRRadiusThumb;
        overlay.layer.cornerCurve = kCACornerCurveContinuous;
        objc_setAssociatedObject(cell, &kOverlayKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (overlay.superview != thumb) [thumb addSubview:overlay];
    if (!CGRectEqualToRect(overlay.frame, thumb.bounds)) overlay.frame = thumb.bounds;
    if (overlay.image != picture) overlay.image = picture;
}

#pragma mark - choosing a photo

@interface SGRFolderPicker : NSObject <PHPickerViewControllerDelegate>
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) void (^done)(void);
@end

@implementation SGRFolderPicker
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    NSItemProvider *provider = results.firstObject.itemProvider;
    if (![provider canLoadObjectOfClass:UIImage.class]) return;
    NSString *name = self.name;
    void (^done)(void) = self.done;
    [provider loadObjectOfClass:UIImage.class completionHandler:^(id<NSItemProviderReading> object, NSError *error) {
        NSData *data = [object isKindOfClass:UIImage.class] ? squareJPEG((UIImage *)object) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (data) save(name, data);
            if (done) done();
        });
    }];
}
@end

static void choosePhoto(NSString *name, void (^done)(void)) {
    PHPickerConfiguration *configuration = [PHPickerConfiguration new];
    configuration.filter = [PHPickerFilter imagesFilter];
    configuration.selectionLimit = 1;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
    SGRFolderPicker *delegate = [SGRFolderPicker new];
    delegate.name = name;
    delegate.done = done;
    picker.delegate = delegate;
    // The picker keeps its delegate weakly, so the picker keeps this one.
    objc_setAssociatedObject(picker, &kDelegateKey, delegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    SGPresentDark(picker);
    [SGTopController() presentViewController:picker animated:YES completion:nil];
}

#pragma mark - the page

static __weak SGModPage *pageOnScreen;

static void reloadPage(void) {
    [pageOnScreen.tableView reloadData];
}

static void editFolder(NSString *name) {
    UIViewController *presenter = SGTopController();
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:name message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    sheet.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [sheet addAction:[UIAlertAction actionWithTitle:@"Choose photo" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        choosePhoto(name, ^{ reloadPage(); });
    }]];
    if (stored()[name]) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Remove picture" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            removePicture(name);
            reloadPage();
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = presenter.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(presenter.view.bounds), CGRectGetMidY(presenter.view.bounds), 1, 1);
    [presenter presentViewController:sheet animated:YES completion:nil];
}

static UIViewController *picturesPage(void) {
    NSArray<NSString *> *names = [NSUserDefaults.standardUserDefaults stringArrayForKey:kSeenKey] ?: @[];
    NSMutableArray<SGModRow *> *rows = [NSMutableArray array];
    for (NSString *name in names) {
        SGModRow *row = SGStatActionRow(name, nil, ^NSString * { return stored()[name] ? @"Picture" : @"None"; }, ^{ editFolder(name); });
        [rows addObject:SGWithSymbol(row, @"folder")];
    }
    if (!rows.count) [rows addObject:SGStatRow(@"No folders listed yet", ^NSString * { return @""; })];
    SGModRow *debug = SGActionRow(@"Copy library debug info", @"What the first rows of Your Library contain, for finding a folder that is not listed", ^{
        NSString *text = dumps().count ? [dumps() componentsJoinedByString:@"\n"] : @"Nothing recorded: open Your Library with Redesigned UI on, then come back.";
        UIPasteboard.generalPasteboard.string = text;
    });
    SGModPage *page = [[SGModPage alloc] initWithTitle:@"Folder pictures"
        intro:@"A photo of your own in place of the gray folder tile in Your Library. A folder is listed once the library has shown it."
        sections:@[
            SGNotedSection(@"Folders", rows, @"Open Your Library, scroll to a folder, then come back. Folders with the same name share one picture."),
            SGSection(nil, @[SGWithSymbol(debug, @"doc.on.clipboard")]),
        ] footer:nil];
    pageOnScreen = page;
    return page;
}

NSArray<SGModRow *> *SGRLibraryAppearanceRows(void) {
    return @[SGWithSymbol(SGPageRow(@"Folder pictures", ^UIViewController * { return picturesPage(); }), @"photo.on.rectangle")];
}
