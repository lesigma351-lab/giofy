// The Home redesign: Spotify's Home page kept, with its controllers, lists and cards, decluttered to a
// music app on black and restyled from the Kit. Its settings, Top picks and Shortcuts on glass, are on the
// Appearance page (HomeSettings.m).
//
//     HomeSections.x   an allow list of the feed's sections: the shortcuts grid, the DJ and the shelves of
//                      cards stay; video and episode previews, episode cards and any new kind collapse. The
//                      DJ loses its heading, and the flags the redesign forces on Home
//     HomeHeader.x     a large title where the filter pills were, the avatar at the trailing edge, no scrim
//     HomeHeadings.x   the shelves' headings in the Music app's size, drawn over Spotify's
//     HomeCards.x      the Encore button every card is: shortcut tiles (HomeTiles.m), continuous corners on the
//                      shelf covers, the DJ card at the card radius without its talking transcript
//     HomeTiles.m      a shortcut tile on glass tinted by its cover (iOS 26), else a surface tinted by it
//     HomeTopPicks.x   Top picks: the first shelf of three cards or more drawn large and paging, as the Music app
//                      draws its Top Picks, under that heading
//     HomeTopPickCard.m a Top picks card: the title and subtitle over the cover's color at its foot
//     HomeCoverColor.x a cover's average color, off the main thread, kept by the picture's URL
//     HomeSettings.m   the rows on the Appearance page
//     HomePerf.x       FLEX builds: the frames of each scroll of Home and the time the hooks above took
//
// Every hook installs only while Redesigned UI is on (SGRedesignedUI).
// Threading: main thread only.
#import <UIKit/UIKit.h>

// Top picks (HomeTopPicks.x): the first shelf drawn large, as the Music app draws its Top Picks. On until switched off.
#define SGRKeyHomeTopPicks @"spotifyglass.redesign.home.topPicks"
// Shortcuts on glass (HomeTiles.m): each shortcut tile on glass tinted by its cover, iOS 26. On until switched off.
#define SGRKeyHomeGlassShortcuts @"spotifyglass.redesign.home.glassShortcuts"
// How vivid Home's cover tints are, 0 to 100 on a slider (HomeSettings.m), 40 to begin with. Shortcut tiles and Top picks
// cards take it when they are drawn, so a change shows after a restart.
#define SGRKeyHomeColor @"spotifyglass.redesign.home.color"
// How large Top picks cards are drawn, in percent of Spotify's size, 120 to 220 on a slider (HomeSettings.m), 170 to begin with.
#define SGRKeyHomeCardSize @"spotifyglass.redesign.home.cardSize"
// Top picks cards that react: a press squishes the card and lights its glass, and a card springs in as it first appears
// (HomeTopPickCard.m). On until switched off.
#define SGRKeyHomeCardReact @"spotifyglass.redesign.home.cardReact"
// A wash of the Top picks cover's color behind the top of Home, sliding as the shelf is swiped (HomeWash.m). On until switched off.
#define SGRKeyHomeWash @"spotifyglass.redesign.home.wash"
@class SGModRow;
NSArray<SGModRow *> *SGRHomeAppearanceRows(void);   // for the Appearance page (App/Pages.m)
// The Color setting as 0...1 (HomeCoverColor.x).
CGFloat SGRHomeColor(void);
// The color with its saturation multiplied by `lift`, capped at 1, hue and brightness kept (HomeCoverColor.x).
UIColor *SGRHomeVivid(UIColor *color, CGFloat lift);

// Whether this shelf (a Home_CarouselKit.TouchCancellingCollectionView) is drawn as Top picks now (HomeTopPicks.x).
BOOL SGRHomeShelfIsTopPicks(UICollectionView *shelf);
// The Top picks shelf `view` is inside, or nil.
UICollectionView *SGRHomeTopPicksShelfAround(UIView *view);
// The heading the Top picks shelf shows in place of Spotify's.
extern NSString *const SGRHomeTopPicksTitle;

// Styles a shelf card (id=Components.UI.HomeCard) as a Top picks card while its shelf is Top picks, and takes that
// style off again when it is not; YES while it is one (HomeTopPickCard.m).
BOOL SGRHomeStyleTopPick(UIView *card);

// The color a Top picks card is drawn in, nil until its cover is read (HomeTopPickCard.m).
UIColor *SGRHomeTopPickColor(UIView *card);
// Keeps the wash in step with the shelf `card` is in (HomeWash.m).
void SGRHomeWashWatch(UIView *card);

// A cover's average color (HomeCoverColor.x): returned when known, else nil, and `later` called on the main thread once
// it is worked out (nil for a picture with no bitmap). Main thread.
UIColor *SGRHomeCoverColor(UIImage *image, void (^later)(UIColor *color));
// The color with its relative luminance held to `ceiling`, hue and saturation kept.
UIColor *SGRHomeDarkened(UIColor *color, CGFloat ceiling);

// Whether HomeSections.x has collapsed the section in this cell.
BOOL SGRHomeSectionCollapsed(UIView *cell);

// Styles a shortcut tile (id=Shortcut.Card.Home) and keeps its picture in step with its cover (HomeTiles.m).
void SGRHomeStyleTile(UIView *tile);

// FLEX builds only (HomePerf.x): a hook takes the time as it starts and hands it back as it ends; outside
// a FLEX build Begin returns 0 and End does nothing.
typedef NS_ENUM(NSUInteger, SGRHomeProbe) {
    SGRHomeProbeSections,
    SGRHomeProbeHeader,
    SGRHomeProbeHeadings,
    SGRHomeProbeCards,
    SGRHomeProbeTiles,
    SGRHomeProbeTopPicks,
    SGRHomeProbeCount,
};
CFTimeInterval SGRHomeProbeBegin(void);
void SGRHomeProbeEnd(SGRHomeProbe probe, CFTimeInterval began);
