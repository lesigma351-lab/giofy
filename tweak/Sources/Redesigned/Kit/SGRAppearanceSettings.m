#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "SGRAccent.h"
#import "SGRTokens.h"

// The motion presets set Bounce and Speed together (SGRTokens.h): Original is the springs the build shipped
// with, the others lean further into overshoot. A pair the sliders land on that is none of them reads as Custom.
static NSArray<NSString *> *motionPresets(void) {
    return @[@"Original", @"Smooth", @"Bouncy", @"Playful", @"Jelly"];
}

static const NSInteger kPresetBounce[] = {0, 15, 40, 70, 100};
static const NSInteger kPresetSpeed[] = {100, 80, 80, 75, 70};

static NSString *motionPresetName(void) {
    NSArray<NSString *> *names = motionPresets();
    for (NSUInteger i = 0; i < names.count; i++) {
        if (SGRMotionBounce() == kPresetBounce[i] && SGRMotionSpeed() == kPresetSpeed[i]) return names[i];
    }
    return @"Custom";
}

// The preset is read off the color stored, so the hooks keep the one key they read and a color set before
// presets existed stays in effect: Apple Music's red reads as Apple Music, Spotify's own (-1) as Spotify, and
// any other color as Custom, the redesign's own green when nothing is stored among them. The custom color
// is put aside while a preset is in place, so Custom brings it back. Follow the cover is a switch of its own
// over whichever color is stored, which stays the accent for a gray cover and outside the player.
static NSArray<NSString *> *presets(void) {
    return @[@"Spotify", @"Apple Music", @"Custom", @"Follow the cover"];
}

static const NSInteger kFollowCover = 3;

static NSInteger colourPreset(void) {
    NSInteger rgb = SGInt(SGRKeyAccent, SGRDefaultAccent);
    if (rgb < 0 || rgb > 0xFFFFFF) return 0;
    return rgb == SGAppleMusicRed ? 1 : 2;
}

static NSInteger preset(void) {
    return SGHidden(SGRKeyAccentFollowsCover) ? kFollowCover : colourPreset();
}

static void choosePreset(NSInteger index) {
    SGSetEnabled(SGRKeyAccentFollowsCover, index == kFollowCover);
    if (index == kFollowCover) return;
    if (colourPreset() == 2) SGSetInt(SGRKeyAccentCustom, SGRAccentRGB());
    NSInteger custom = SGInt(SGRKeyAccentCustom, SGRDefaultAccent);
    if (custom < 0 || custom > 0xFFFFFF) custom = SGRDefaultAccent;
    SGSetInt(SGRKeyAccent, index == 0 ? -1 : index == 1 ? SGAppleMusicRed : custom);
}

// The redesign's rows of the Appearance page (App/Pages.m): the preset from a menu, then the color in effect,
// which opens the picker; a color stored from there is Custom (and ends Follow the cover). AMOLED has no row: the redesign is always black.
NSArray<SGModRow *> *SGRAppearanceRows(void) {
    SGModRow *menu = SGMenuRow(@"Accent color preset", presets(), ^NSString *{ return presets()[(NSUInteger)preset()]; },
                               ^(NSInteger index) { choosePreset(index); });
    SGModRow *colour = SGStatActionRow(@"Accent color", nil, ^NSString *{ return [NSString stringWithFormat:@"#%06lX", (long)SGRAccentRGB()]; }, ^{
        SGPickColor(@"Accent color", SGRAccentRGB(), ^(NSInteger rgb) {
            SGSetInt(SGRKeyAccent, rgb);
            SGSetInt(SGRKeyAccentCustom, rgb);
            SGSetEnabled(SGRKeyAccentFollowsCover, NO);
        });
    });
    colour.swatch = ^UIColor *{ return SGColorRGB(SGRAccentRGB()); };

    // Motion: a preset, and the two sliders it sets. They apply as they are dragged, to every animation of the
    // redesign that runs through SGRAnimate; Reduce Motion still turns the springs off.
    SGModRow *motion = SGMenuRow(@"Motion", motionPresets(), ^NSString *{ return motionPresetName(); }, ^(NSInteger index) {
        SGSetInt(SGRKeyMotionBounce, kPresetBounce[index]);
        SGSetInt(SGRKeyMotionSpeed, kPresetSpeed[index]);
    });
    SGModRow *bounce = SGSliderRow(@"Bounce", @"How far springs overshoot before they settle. 0 is none.", 0, 100, 5,
                                   ^double { return (double)SGRMotionBounce(); },
                                   ^(double value) { SGSetInt(SGRKeyMotionBounce, (NSInteger)value); },
                                   ^NSString *(double value) { return [NSString stringWithFormat:@"%d%%", (int)value]; });
    SGModRow *speed = SGSliderRow(@"Speed", @"How fast animations play. Lower is slower and smoother, 100% is the original.", 50, 150, 5,
                                  ^double { return (double)SGRMotionSpeed(); },
                                  ^(double value) { SGSetInt(SGRKeyMotionSpeed, (NSInteger)value); },
                                  ^NSString *(double value) { return [NSString stringWithFormat:@"%d%%", (int)value]; });
    return @[
        SGWithSymbol(menu, @"paintpalette"),
        SGWithSymbol(colour, @"eyedropper"),
        SGWithSymbol(SGOptionRow(@"Plain checkmark", @"A saved song's tick without its circle, in the accent", SGRKeyPlainCheck), @"checkmark"),
        SGWithSymbol(motion, @"sparkles"),
        SGWithSymbol(bounce, @"waveform.path"),
        SGWithSymbol(speed, @"speedometer"),
        SGWithSymbol(SGSwitchRow(@"Springy player", @"The player opens and closes on a spring of its own, with the Bounce and Speed above. Off leaves Spotify's animation.", SGRKeyMotionPlayer), @"arrow.up.and.down.circle"),
    ];
}
