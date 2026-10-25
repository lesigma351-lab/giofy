// The now playing bar's rows of the redesign, the Mini player section of the Player page
// (Redesigned/Player/PlayerSettings.m puts them there).
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Redesigned/Navbar/Navbar.h"
#import "NowPlayingBar.h"

NSArray<SGModRow *> *SGRNowPlayingBarRows(void) {
    // The tab bar reads the switch as each scroll goes; a bar minimized when it goes off grows back at once.
    SGModRow *minimize = SGSwitchRow(@"Apple Music style", @"Between two tabs as a page scrolls down", SGRKeyNavbarMinimize);
    minimize.changed = ^(BOOL on) {
        if (!on) SGRSetTabBarMinimized(NO, NO);
        SGRRefreshTabBar();
    };
    SGModRow *inlineConnect = SGOptionRow(@"Device button", @"Kept on the bar between the tabs", SGRKeyBarInlineConnect);
    inlineConnect.waitsOn = SGRKeyNavbarMinimize;
    return @[
        minimize,
        inlineConnect,
        SGHideRow(@"Hide the device button", @"On the full now playing bar", SGRHideBarConnect),
    ];
}

// Gio's additions to the bar.
NSArray<SGModRow *> *SGRBarGioRows(void) {
    return @[
        SGWithSymbol(SGSwitchRow(@"Artist in the tab bar row", @"The artist under the title on the card between the tabs", SGRKeyBarRowArtist), @"text.line.2.summary"),
        SGWithSymbol(SGOptionRow(@"Progress line in the tab bar row", @"The line under the text on the card between the tabs", SGRKeyBarRowProgress), @"minus"),
        SGWithSymbol(SGSliderRow(@"Bar bounce", @"How much the bar pops as the player closes into it. 0 is none.", 0, 100, 5,
                                 ^double { return (double)SGInt(SGRKeyBarBounce, 60); },
                                 ^(double value) { SGSetInt(SGRKeyBarBounce, (NSInteger)value); },
                                 ^NSString *(double value) { return [NSString stringWithFormat:@"%d%%", (int)value]; }), @"arrow.down.to.line.compact"),
    ];
}
