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
#import "Redesigned/NowPlayingBar/NowPlayingBar.h"
#import "Pages.h"

// The view tree of the player, taken while it was open (the player's views are gone once it closes), for working out where
// its buttons are: class, identifier and frame, indented.
static void copyPlayerLayout(void) {
    NSString *dump = SGRPlayerLayoutDump();
    UIPasteboard.generalPasteboard.string = dump.length ? dump : @"The player's layout has not been taken yet: open the player, leave it open a second or two, then come back to Mod Settings.";
}

SGModSection *SGGioSection(void) {
    NSMutableArray<SGModRow *> *rows = [NSMutableArray array];
    BOOL (^redesigned)(void) = ^BOOL { return SGRedesignedUIStored(); };
    NSMutableArray<SGModRow *> *looks = [NSMutableArray array];
    [looks addObjectsFromArray:SGRGioMotionRows()];
    [looks addObjectsFromArray:SGRHomeGioRows()];
    [looks addObjectsFromArray:SGRPlayerGioRows()];
    [looks addObjectsFromArray:SGRBarGioRows()];
    [looks addObjectsFromArray:SGRLibraryAppearanceRows()];
    for (SGModRow *row in looks) row.visible = redesigned;
    [rows addObjectsFromArray:looks];
    [rows addObject:SGMusicOnlyRow()];
    SGModRow *debug = SGActionRow(@"Copy player layout", @"Open the player and leave it up a second or two, then copy what it is made of to paste back to Claude.", ^{ copyPlayerLayout(); });
    debug.visible = redesigned;
    [rows addObject:debug];
    return SGSection(@"Gio's additions", rows);
}
