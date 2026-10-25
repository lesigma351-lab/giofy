// "Gio's additions": one section on Mod Settings' main page with every switch and slider that was not in the mod before.
// The rows are each layer's own (the motion sliders, Home, the player, Library folders, Music only); this only gathers them.
// The redesign's rows hide under the native look, which has none of them.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Shared/MusicOnly/MusicOnly.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Home/Home.h"
#import "Redesigned/Library/Library.h"
#import "Redesigned/Player/Player.h"
#import "Pages.h"

// The view tree under the player's classes, for working out where its buttons are: class, identifier and frame, indented.
static void dump(UIView *view, NSInteger depth, NSMutableString *out, NSInteger *lines) {
    if (*lines >= 450 || depth > 9) return;
    (*lines)++;
    [out appendFormat:@"%*s%@ id=%@ %@%@\n", (int)depth * 2, "", NSStringFromClass(view.class), view.accessibilityIdentifier ?: @"-",
     NSStringFromCGRect(view.frame), view.hidden || view.alpha < 0.01 ? @" hidden" : @""];
    for (UIView *sub in view.subviews) dump(sub, depth + 1, out, lines);
}

static void copyPlayerLayout(void) {
    NSMutableString *out = [NSMutableString string];
    NSInteger lines = 0;
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
            if (candidate.isKeyWindow) window = candidate;
        }
    }
    __block UIView *start = nil;
    if (window) SGForEachView(window, ^(UIView *v) {
        if (!start && [NSStringFromClass(v.class) containsString:@"NowPlaying_ModesImpl"]) start = v;
    });
    while (start.superview && ![NSStringFromClass(start.superview.class) containsString:@"UITransitionView"] && ![start.superview isKindOfClass:UIWindow.class]) {
        UIView *up = start.superview;
        if ([NSStringFromClass(up.class) containsString:@"CollectionView"]) break;
        start = up;
    }
    if (start) dump(start, 0, out, &lines);
    else [out appendString:@"The player was not found: open it, then come back to Mod Settings."];
    UIPasteboard.generalPasteboard.string = out;
}

SGModSection *SGGioSection(void) {
    NSMutableArray<SGModRow *> *rows = [NSMutableArray array];
    BOOL (^redesigned)(void) = ^BOOL { return SGRedesignedUIStored(); };
    NSMutableArray<SGModRow *> *looks = [NSMutableArray array];
    [looks addObjectsFromArray:SGRGioMotionRows()];
    [looks addObjectsFromArray:SGRHomeGioRows()];
    [looks addObjectsFromArray:SGRPlayerGioRows()];
    [looks addObjectsFromArray:SGRLibraryAppearanceRows()];
    for (SGModRow *row in looks) row.visible = redesigned;
    [rows addObjectsFromArray:looks];
    [rows addObject:SGMusicOnlyRow()];
    SGModRow *debug = SGActionRow(@"Copy player layout", @"Open the player first, then copy what it is made of to paste back to Claude.", ^{ copyPlayerLayout(); });
    debug.visible = redesigned;
    [rows addObject:debug];
    return SGSection(@"Gio's additions", rows);
}
