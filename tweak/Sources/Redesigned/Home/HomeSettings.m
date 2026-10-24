// Home redesign: its rows on the Appearance page, under the redesign's own (App/Pages.m). Both are read at launch.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Home.h"

NSArray<SGModRow *> *SGRHomeAppearanceRows(void) {
    return @[
        SGWithSymbol(SGSwitchRow(@"Top picks", @"Home's first shelf drawn large, as the Music app's Top Picks", SGRKeyHomeTopPicks), @"rectangle.stack"),
        SGWithSymbol(SGSwitchRow(@"Cards first", @"Top picks above the shortcuts, at the very top of Home", SGRKeyHomeCardsFirst), @"arrow.up.to.line"),
        SGWithSymbol(SGSliderRow(@"Card size", @"How large Top picks cards are drawn. 100% is Spotify's size.", 120, 220, 10,
                                 ^double { return (double)SGInt(SGRKeyHomeCardSize, 170); },
                                 ^(double value) { SGSetInt(SGRKeyHomeCardSize, (NSInteger)value); },
                                 ^NSString *(double value) { return [NSString stringWithFormat:@"%d%%", (int)value]; }), @"arrow.up.left.and.arrow.down.right"),
        SGWithSymbol(SGSwitchRow(@"Reactive cards", @"Top picks cards squish and shine on touch, and spring in", SGRKeyHomeCardReact), @"hand.tap"),
        SGWithSymbol(SGSwitchRow(@"Color wash", @"Home's top glows in the color of the Top picks cover in view", SGRKeyHomeWash), @"circle.lefthalf.filled.righthalf.striped.horizontal"),
        SGWithSymbol(SGSwitchRow(@"Shortcuts on glass", @"Home's shortcuts on glass tinted by their covers", SGRKeyHomeGlassShortcuts), @"square.grid.2x2"),
        SGWithSymbol(SGSliderRow(@"Home color", @"How vivid the cover tints on Home are. 0 is the original, muted look.", 0, 100, 10,
                                 ^double { return (double)SGInt(SGRKeyHomeColor, 40); },
                                 ^(double value) { SGSetInt(SGRKeyHomeColor, (NSInteger)value); },
                                 ^NSString *(double value) { return [NSString stringWithFormat:@"%d%%", (int)value]; }), @"paintpalette.fill"),
    ];
}
