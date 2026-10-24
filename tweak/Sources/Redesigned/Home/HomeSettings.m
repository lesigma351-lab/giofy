// Home redesign: its rows on the Appearance page, under the redesign's own (App/Pages.m). Both are read at launch.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Home.h"

NSArray<SGModRow *> *SGRHomeAppearanceRows(void) {
    return @[
        SGWithSymbol(SGSwitchRow(@"Top picks", @"Home's first shelf drawn large, as the Music app's Top Picks", SGRKeyHomeTopPicks), @"rectangle.stack"),
        SGWithSymbol(SGSwitchRow(@"Shortcuts on glass", @"Home's shortcuts on glass tinted by their covers", SGRKeyHomeGlassShortcuts), @"square.grid.2x2"),
        SGWithSymbol(SGSliderRow(@"Home color", @"How vivid the cover tints on Home are. 0 is the original, muted look.", 0, 100, 10,
                                 ^double { return (double)SGInt(SGRKeyHomeColor, 40); },
                                 ^(double value) { SGSetInt(SGRKeyHomeColor, (NSInteger)value); },
                                 ^NSString *(double value) { return [NSString stringWithFormat:@"%d%%", (int)value]; }), @"paintpalette.fill"),
    ];
}
