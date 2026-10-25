// Home redesign: its rows on the Appearance page, under the redesign's own (App/Pages.m). Both are read at launch.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Home.h"

static NSString *percent(double value) {
    return [NSString stringWithFormat:@"%d%%", (int)value];
}

// The two rows that were always there.
NSArray<SGModRow *> *SGRHomeAppearanceRows(void) {
    return @[
        SGWithSymbol(SGSwitchRow(@"Top picks", @"Home's first shelf drawn large, as the Music app's Top Picks", SGRKeyHomeTopPicks), @"rectangle.stack"),
        SGWithSymbol(SGSwitchRow(@"Shortcuts on glass", @"Home's shortcuts on glass tinted by their covers", SGRKeyHomeGlassShortcuts), @"square.grid.2x2"),
    ];
}

// Gio's additions to Home.
NSArray<SGModRow *> *SGRHomeGioRows(void) {
    return @[
        SGWithSymbol(SGSwitchRow(@"Cards first", @"Top picks above the shortcuts, at the very top of Home", SGRKeyHomeCardsFirst), @"arrow.up.to.line"),
        SGWithSymbol(SGSliderRow(@"Card size", @"How large Top picks cards are drawn, against Spotify's own size. Restart to apply.", 120, 220, 10,
                                 ^double { return (double)SGInt(SGRKeyHomeCardSize, 170); },
                                 ^(double value) { SGSetInt(SGRKeyHomeCardSize, (NSInteger)value); }, ^NSString *(double value) { return percent(value); }), @"arrow.up.left.and.arrow.down.right"),
        SGWithSymbol(SGSwitchRow(@"Reactive cards", @"Top picks cards squish and shine on touch, and spring in", SGRKeyHomeCardReact), @"hand.tap"),
        SGWithSymbol(SGSliderRow(@"Card squish", @"How far a card shrinks under your finger.", 0, 25, 1,
                                 ^double { return (double)SGInt(SGRKeyHomeCardSquish, 9); },
                                 ^(double value) { SGSetInt(SGRKeyHomeCardSquish, (NSInteger)value); }, ^NSString *(double value) { return percent(value); }), @"arrow.down.right.and.arrow.up.left"),
        SGWithSymbol(SGSwitchRow(@"Color wash", @"Home's top glows in the color of the Top picks cover in view", SGRKeyHomeWash), @"circle.lefthalf.filled.righthalf.striped.horizontal"),
        SGWithSymbol(SGSliderRow(@"Wash strength", @"How strong the glow is. Restart to apply.", 0, 100, 5,
                                 ^double { return (double)SGInt(SGRKeyHomeWashStrength, 95); },
                                 ^(double value) { SGSetInt(SGRKeyHomeWashStrength, (NSInteger)value); }, ^NSString *(double value) { return percent(value); }), @"sun.max"),
        SGWithSymbol(SGSliderRow(@"Wash depth", @"How far down the page the glow reaches, in points. Restart to apply.", 300, 1000, 20,
                                 ^double { return (double)SGInt(SGRKeyHomeWashDepth, 620); },
                                 ^(double value) { SGSetInt(SGRKeyHomeWashDepth, (NSInteger)value); }, ^NSString *(double value) { return [NSString stringWithFormat:@"%d", (int)value]; }), @"arrow.down.to.line"),
        SGWithSymbol(SGSliderRow(@"Home color", @"How vivid the cover tints on Home are. 0 is the original, muted look.", 0, 100, 10,
                                 ^double { return (double)SGInt(SGRKeyHomeColor, 40); },
                                 ^(double value) { SGSetInt(SGRKeyHomeColor, (NSInteger)value); }, ^NSString *(double value) { return percent(value); }), @"paintpalette.fill"),
    ];
}
