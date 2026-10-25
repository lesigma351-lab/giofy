// Player redesign: glass circles behind the header's close and more buttons.
//
// Glass is the control layer floating over the field, so it goes behind the round buttons only: the
// playlist name between them stays a label, and the row of playback controls stays bare glyphs
// (PlayerControls.x). Each circle is a subview of the button it sits behind (SGRGlassInside), below
// what the button draws and taking no touches, so the buttons stay Spotify's, with their actions, state
// and accessibility, and the circle follows the button wherever Spotify's row puts it. Circles placed
// from the unit's layout pass instead (a backing across the unit's view) were read before the row had
// laid the buttons out and sat 24pt up and to the side until a tap laid the unit out again
// (trees/continuous/1.txt, 2026-09-17: shapes at {-10, -22} and {320, -22}; the close button is at {12, 0}
// in the unit's view, so its circle belonged at {14, 2}).
//
// The add button keeps no circle: its glyph is a circle of its own, green and filled once the track is
// saved, and on glass it read as a disc on a disc (device test, 2026-09-17).
//
// Tree (trees/clean/player/01.txt): HeaderElementsUnit's view is a 402x48 row holding
// id=now-playing-minimize-button 48x48 (:103) and id=Context menu 48x48 (:122), the playlist name
// between them. The down arrow and the ⋯ are a pair, as the Music app's are: the same circle, size and glass.
// 9.1.78 also carries mobile-nowplaying-close-button (strings in the binary), so the down arrow is looked for
// under either name; which view each circle went into is logged once, so a phone where the arrow has none
// says why.
//
// The circle presses in itself (scale, the Kit's press spring), from the control that takes the touches: the
// arrow's own, and for the ⋯ the mod's button over it (ContextMenu.x). Spotify draws a button's pressed look
// under its subviews, where the circle covers it (phone, 2026-10-06: the arrow closed the player but showed
// no ripple), and the ⋯'s touches no longer reach Spotify's button at all.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/ContextMenu/ContextMenu.h"
#import "Player.h"

static char kGlassKey, kCloseKey, kMoreKey, kPressKey;
static const CGFloat kPressScale = 0.92;

@interface SGRHeaderPress : NSObject
@end
@implementation SGRHeaderPress
// The circle of the control pressed, or of the button under it (the ⋯'s front).
static UIView *circleOf(UIControl *control) {
    return objc_getAssociatedObject(control, &kGlassKey) ?: objc_getAssociatedObject(control.superview, &kGlassKey);
}
- (void)down:(UIControl *)control {
    UIView *circle = circleOf(control);
    SGRAnimate(SGRMotionPress, ^{ circle.transform = CGAffineTransformMakeScale(kPressScale, kPressScale); }, nil);
}
- (void)up:(UIControl *)control {
    UIView *circle = circleOf(control);
    SGRAnimate(SGRMotionPress, ^{ circle.transform = CGAffineTransformIdentity; }, nil);
}
@end

// `throughMenu`: the mod's ⋯, whose touch UIKit cancels as the menu comes up on it; the press holds until the
// menu ends, which the button reports as a touch up outside (ContextMenu.x), so its cancel is not listened to.
static void pressFrom(UIControl *control, BOOL throughMenu) {
    if (![control isKindOfClass:UIControl.class] || objc_getAssociatedObject(control, &kPressKey)) return;
    objc_setAssociatedObject(control, &kPressKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    static SGRHeaderPress *press;
    if (!press) press = [SGRHeaderPress new];
    [control addTarget:press action:@selector(down:) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    UIControlEvents up = UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchDragExit;
    [control addTarget:press action:@selector(up:) forControlEvents:throughMenu ? up : up | UIControlEventTouchCancel];
}

// `identifiers` holds, for each button, the identifiers it may carry, the first found winning.
static void glassInside(UIViewController *unit, NSArray<NSArray<NSString *> *> *identifiers, const void **findKeys) {
    UIView *host = unit.viewIfLoaded;
    if (!host) return;
    NSUInteger found = 0;
    for (NSUInteger i = 0; i < identifiers.count; i++) {
        UIView *button = nil;
        for (NSString *identifier in identifiers[i]) {
            if ((button = SGRFindByIdentifier(host, identifier, findKeys[i]))) break;
        }
        NSString *name = identifiers[i].firstObject;
        static NSMutableSet<NSString *> *said;
        if (!said) said = [NSMutableSet set];
        if (!button) {
            if (![said containsObject:name]) {
                [said addObject:name];
                SGLog(@"redesign player: %@ not found in %@, left as Spotify's", [identifiers[i] componentsJoinedByString:@" or "], NSStringFromClass(host.class));
            }
            continue;
        }
        UIView *circle = SGRGlassInside(button, &kGlassKey, SGRGlassCircleSize);
        if (![said containsObject:name] && button.bounds.size.width > 0) {
            [said addObject:name];
            SGLog(@"redesign player: a %.0fpt glass circle in %@ (id %@, %.0fx%.0f, %@)", circle.bounds.size.width, NSStringFromClass(button.class),
                  button.accessibilityIdentifier, button.bounds.size.width, button.bounds.size.height,
                  button.hidden || button.alpha < 0.01 ? @"hidden" : @"shown");
        }
        if ([name isEqualToString:@"Context menu"]) {
            SGRPlayerMenuWatch(button);
        }
        UIControl *front = SGRSystemMenuFront(button);
        pressFrom(front ?: (UIControl *)button, front != nil);
        found++;
    }

    static NSMutableSet<NSString *> *logged;
    if (!logged) logged = [NSMutableSet set];
    NSString *unitName = NSStringFromClass(unit.class);
    if (![logged containsObject:unitName]) {
        [logged addObject:unitName];
        SGLog(@"redesign player: glass inside %lu of %lu buttons in %@", (unsigned long)found, (unsigned long)identifiers.count, unitName);
    }
}

#pragma mark - the player's layout, for Mod Settings

static NSString *sLayoutDump;

NSString *SGRPlayerLayoutDump(void) {
    return sLayoutDump;
}

static void dumpTree(UIView *view, NSInteger depth, NSMutableString *out, NSInteger *lines) {
    if (*lines >= 900 || depth > 18) return;
    (*lines)++;
    [out appendFormat:@"%*s%@ id=%@ %@%@\n", (int)depth * 2, "", NSStringFromClass(view.class), view.accessibilityIdentifier ?: @"-",
     NSStringFromCGRect(view.frame), view.hidden || view.alpha < 0.01 || view.layer.hidden ? @" hidden" : @""];
    for (UIView *sub in view.subviews) dumpTree(sub, depth + 1, out, lines);
}

// A moment after the header lays out the player is up and settled: its tree is kept, since the views are gone by the time
// Mod Settings is open.
static void keepLayout(UIView *host) {
    static BOOL pending;
    static CFTimeInterval last;
    if (pending || CACurrentMediaTime() - last < 3) return;
    pending = YES;
    __weak UIView *weak = host;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        pending = NO;
        last = CACurrentMediaTime();
        UIView *start = weak;
        if (!start.window) return;
        while (start.superview && ![NSStringFromClass(start.superview.class) containsString:@"UITransitionView"] && ![start.superview isKindOfClass:UIWindow.class]) {
            UIView *up = start.superview;
            if ([NSStringFromClass(up.class) containsString:@"CollectionView"]) break;
            start = up;
        }
        NSMutableString *out = [NSMutableString string];
        NSInteger lines = 0;
        dumpTree(start, 0, out, &lines);
        sLayoutDump = out;
    });
}

#pragma mark - the compact header

// The Music app's header: a grabber over the player instead of the arrow and the playlist's name, and the ⋯ down at the
// right of the like. Spotify's controls stay Spotify's: the ⋯ is moved by a transform (which survives its row laying
// out again) and a view of the mod's over the player hands it the touches it no longer has room for in its own row.
static char kAddFindKey, kGrabberKey, kMoreReachKey;
static __weak UIView *sg_like, *sg_likeRoot;

@interface SGRMoreReach : UIView
@property (nonatomic, weak) UIView *more;
@end
@implementation SGRMoreReach
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *more = self.more;
    if (!more.window || self.hidden || ![self pointInside:point withEvent:event]) return nil;
    return [more hitTest:[more convertPoint:point fromView:self] withEvent:event];
}
@end

@interface SGRGrabber : UIView
@property (nonatomic, weak) UIControl *minimize;
@end
@implementation SGRGrabber
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    UIView *pill = [[UIView alloc] initWithFrame:CGRectMake((frame.size.width - 36) / 2, (frame.size.height - 5) / 2, 36, 5)];
    pill.backgroundColor = [UIColor colorWithWhite:1 alpha:0.4];
    pill.layer.cornerRadius = 2.5;
    pill.userInteractionEnabled = NO;
    pill.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [self addSubview:pill];
    [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)]];
    return self;
}
- (void)tapped {
    [self.minimize sendActionsForControlEvents:UIControlEventTouchUpInside];
}
@end

// The view the stack arranges around `view`, when it is no wider than a button; `view` itself otherwise.
static UIView *buttonHolder(UIView *view, UIView *upto) {
    for (UIView *v = view; v && v != upto; v = v.superview) {
        if ([v.superview isKindOfClass:UIStackView.class]) return v.bounds.size.width <= 100 ? v : view;
    }
    return view;
}

static void compactHeader(UIViewController *unit) {
    UIView *host = unit.viewIfLoaded;
    if (!host) return;
    UIView *close = SGRFindByIdentifier(host, @"now-playing-minimize-button", &kCloseKey) ?: SGRFindByIdentifier(host, @"mobile-nowplaying-close-button", &kCloseKey);
    UIView *more = SGRFindByIdentifier(host, @"Context menu", &kMoreKey);
    if (close) SGRPlayerVanish(close);
    // The playlist's name between them.
    SGForEachView(host, ^(UIView *v) {
        if ([v isKindOfClass:UILabel.class]) v.layer.hidden = YES;
    });

    SGRGrabber *grabber = objc_getAssociatedObject(host, &kGrabberKey);
    if (!grabber) {
        grabber = [[SGRGrabber alloc] initWithFrame:CGRectMake(0, 0, 96, 28)];
        objc_setAssociatedObject(host, &kGrabberKey, grabber, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    grabber.minimize = (UIControl *)close;
    if (grabber.superview != host) [host addSubview:grabber];
    grabber.center = CGPointMake(CGRectGetMidX(host.bounds), 9);
    [host bringSubviewToFront:grabber];

    if (!more) return;
    SGRPlayerMenuWatch(more);
    // The like: the Add button of the title row, found from the nearest view over the header that holds one.
    UIView *like = sg_like, *root = sg_likeRoot;
    if (!like.window || !root || ![like isDescendantOfView:root]) {
        like = root = nil;
        NSUInteger depth = 0;
        for (UIView *up = host.superview; up && !like && depth < 14; up = up.superview, depth++) {
            like = SGRFindByIdentifier(up, @"Components.UI.AddToButton", &kAddFindKey);
            if (like) root = up;
        }
        sg_like = like;
        sg_likeRoot = root;
    }
    static NSUInteger tries;
    UIView *moreHolder = buttonHolder(more, host), *likeHolder = like ? buttonHolder(like, root) : nil;
    if (!like || likeHolder.bounds.size.width < 1 || moreHolder.bounds.size.width < 1) {
        if (tries++ < 20) {
            __weak UIView *weakHost = host;
            dispatch_async(dispatch_get_main_queue(), ^{ [weakHost setNeedsLayout]; });
        }
        return;
    }
    tries = 0;
    // Where each stands without its own transform, in the player's coordinates.
    CGPoint moreAt = [moreHolder.superview convertPoint:moreHolder.center toView:root];
    CGPoint likeAt = [likeHolder.superview convertPoint:likeHolder.center toView:root];
    CGAffineTransform toLike = CGAffineTransformMakeTranslation(round(likeAt.x - moreAt.x), round(likeAt.y - moreAt.y));
    CGAffineTransform aside = CGAffineTransformMakeTranslation(-50, 0);
    if (!CGAffineTransformEqualToTransform(moreHolder.transform, toLike)) moreHolder.transform = toLike;
    if (!CGAffineTransformEqualToTransform(likeHolder.transform, aside)) likeHolder.transform = aside;

    SGRMoreReach *reach = objc_getAssociatedObject(host, &kMoreReachKey);
    if (!reach) {
        reach = [SGRMoreReach new];
        objc_setAssociatedObject(host, &kMoreReachKey, reach, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    reach.more = more;
    if (reach.superview != root) [root addSubview:reach];
    CGRect drawn = [more convertRect:more.bounds toView:root];
    CGRect frame = CGRectInset(drawn, MIN(0, (drawn.size.width - 44) / 2), MIN(0, (drawn.size.height - 44) / 2));
    if (!CGRectEqualToRect(reach.frame, frame)) reach.frame = frame;
    [root bringSubviewToFront:reach];

    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGLog(@"redesign player: compact header, the ⋯ moved by %@ to the like, which moves by -50", NSStringFromCGAffineTransform(toLike)); });
}

%hook _TtC20NowPlaying_ModesImpl18HeaderElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    UIView *shown = ((UIViewController *)self).viewIfLoaded;
    if (shown) keepLayout(shown);
    if (SGEnabled(SGRKeyCompactHeader)) {
        compactHeader((UIViewController *)self);
        return;
    }
    static const void *keys[] = {&kCloseKey, &kMoreKey};
    glassInside((UIViewController *)self, @[@[@"now-playing-minimize-button", @"mobile-nowplaying-close-button"], @[@"Context menu"]], keys);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"_TtC20NowPlaying_ModesImpl18HeaderElementsUnit"]);
}
