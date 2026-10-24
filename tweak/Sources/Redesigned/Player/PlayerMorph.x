// Player redesign: the player grows out of the now playing bar's card and the cover flies out of the
// card's artwork, the way the Music app opens its player, instead of Spotify's slide up and fade.
//
// Spotify 9.1.78 runs the open and the close through SPTBarOverlayPresentationTransition: it hides the
// real bar and tab bar, moves stand-ins, and sets -setProgress: (0 the bar, 1 the player, clamped) on
// every frame of its own display link, from a spring when tapped and from the finger when dragged
// (setProgress: at 0x109815464). There it sets the player's frame to the container's bounds moved down by
// the bar's bottom edge times (1 - progress), and the player's alpha, and moves and fades the bar's stand-in.
//
// The morph rides on that progress, after Spotify's own, so taps, drags and canceled drags follow:
//   the sheet   a rounded rect from the card's frame and radius to the screen's, filled with the
//               field's color, under the player, showing at once;
//   the player  masked to the sheet, its content scaled and moved so its top left is the sheet's
//               (sublayerTransform, and the frame's top moved to the sheet's; Spotify's gesture code
//               reads back only the frame's height), its own background color lifted off meanwhile
//               (a sublayerTransform does not move it), and faded in over the first part of the growth;
//   the bar     Spotify's stand-in riding the sheet's top edge, gone by a quarter of the way;
//   the tab bar Spotify's stand-in hidden, since the real one stays in view around the sheet
//               and the stand-in would be a second tab bar;
//   the cover   a copy flown from the card's artwork to the player's cover, moved within the sheet,
//               the player's own cover and shadow hidden meanwhile.
// All of it is taken down in -destroyTransitioningContext, which Spotify calls from -animationEnded:.
//
// Skipped on a regular width (Spotify's iPad branch), with Reduce Motion on, or while the bar has no
// card (hidden, not styled yet): Spotify's own transition then runs untouched.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/NowPlayingBar/NowPlayingBar.h"
#import "Player.h"

@interface SPTBarOverlayPresentationTransition : NSObject
- (id<UIViewControllerContextTransitioning>)transitioningContext;
- (UIView *)overlayView;
- (UIView *)barSnapshotView;
- (UIView *)tabBarSnapshotView;
- (CGRect)barFrame;
- (double)progress;
@end

static const CGFloat kScreenRadiusFallback = 55;

// What a spring's overshoot becomes, since the sheet cannot go past the card or the screen by a fraction of its
// travel (the card to the screen is 800 pt, so 10% would be 80): each unit of overshoot swells the sheet by this
// many points on every side, up to the limit. Opening, the player swells a little past the screen's edges and
// settles; closing, the card swells a little past its own size and settles.
static const CGFloat kPopPoints = 160, kPopLimit = 24;

static CGFloat lerp(CGFloat a, CGFloat b, CGFloat t) {
    return a + (b - a) * t;
}

static CGRect lerpRect(CGRect a, CGRect b, CGFloat t) {
    return CGRectMake(lerp(a.origin.x, b.origin.x, t), lerp(a.origin.y, b.origin.y, t),
                      lerp(a.size.width, b.size.width, t), lerp(a.size.height, b.size.height, t));
}

// 0 until `from`, 1 from `to`, eased between.
static CGFloat ramp(CGFloat from, CGFloat to, CGFloat t) {
    CGFloat x = MIN(1, MAX(0, (t - from) / (to - from)));
    return x * x * (3 - 2 * x);
}

// The step response of a spring: 0 at the start, 1 once it has settled, overshooting by what `damping` (the damping
// ratio, under 1) allows. It starts at rest and picks up quickly, about half the way in a sixth of `duration`. Its
// envelope is down to 0.5% by `duration`, so a spring cut off there jumps by a few points at most.
static CGFloat springStep(CFTimeInterval elapsed, CFTimeInterval duration, CGFloat damping) {
    if (duration <= 0 || elapsed >= duration) return 1;
    double zeta = MIN(0.95, MAX(0.2, damping));
    double omega = 5.3 / (zeta * duration);
    double root = sqrt(1 - zeta * zeta);
    double decay = exp(-zeta * omega * elapsed);
    return 1 - decay * (cos(omega * root * elapsed) + zeta / root * sin(omega * root * elapsed));
}

// The damping ratio for the Bounce slider (SGRTokens.h): 0 is a spring that does not overshoot, 40 gives back a
// tenth of its travel, 70 about a fifth and 100 over a quarter.
static CGFloat playerDamping(void) {
    static const CGFloat bounce[] = {0, 40, 70, 100}, ratio[] = {0.95, 0.59, 0.48, 0.375};
    CGFloat value = SGRMotionBounce();
    for (int i = 1; i < 4; i++) {
        if (value <= bounce[i]) return ratio[i - 1] + (ratio[i] - ratio[i - 1]) * (value - bounce[i - 1]) / (bounce[i] - bounce[i - 1]);
    }
    return ratio[3];
}

static CGFloat screenRadius(void) {
    static CGFloat radius;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        radius = kScreenRadiusFallback;
        @try {
            id value = [UIScreen.mainScreen valueForKey:@"_displayCornerRadius"];
            if ([value respondsToSelector:@selector(doubleValue)] && [value doubleValue] > 0) radius = [value doubleValue];
        } @catch (__unused NSException *e) {}
    });
    return radius;
}

@interface SGRPlayerMorph : NSObject
@property (nonatomic, readonly) CGFloat cardTop;
// Lets -apply: take a progress below 0 or above 1 (up to 0.3 either way) as the sheet swelling past the card or the
// screen; without it the progress is held between them, which is what Spotify's own never leaves.
- (void)allowOvershoot;
// 9.1.78's progress never leaves 0...1, so this adds the bounce: opening, the sheet swells past the screen as it arrives and
// settles back; closing, the card swells past its own size as it lands. Zero at both ends, so a still player is untouched.
- (CGFloat)bounced:(CGFloat)progress;
@end

@implementation SGRPlayerMorph {
    __weak UIView *_container, *_overlay, *_bar;
    UIView *_sheet;
    UIImageView *_cover;
    CALayer *_mask;
    CGRect _card, _barArtwork, _barRest, _spotifyFrame;
    CGFloat _cardRadius, _spotifyAlpha;
    CGColorRef _overlayColor;
    BOOL _coverHidden;
    BOOL _follows;   // 9.1.90: Spotify animates the player's frame and alpha, which the morph then only reads
    BOOL _overshoot; // the progress may leave 0...1 (allowOvershoot)
    CGFloat _lastT;  // the last progress applied, 0 the card and 1 the player
    CGFloat _lastP;  // the last progress Spotify set (bounced:)
    BOOL _opening;   // which way it was last going
}

- (CGFloat)bounced:(CGFloat)progress {
    if (!_overshoot) return progress;
    if (progress != _lastP) _opening = progress > _lastP;
    _lastP = progress;
    if (progress <= 0 || progress >= 1) return progress;
    // The Bounce slider's share of the travel, swung once past the end and once back over the last 45% of the way.
    CGFloat amplitude = 0.28 * SGRMotionBounce() / 100.0;
    CGFloat u = ((_opening ? progress : 1 - progress) - 0.55) / 0.45;
    if (u <= 0) return progress;
    CGFloat swing = amplitude * sin(2 * M_PI * u) * (1 - 0.4 * u);
    return _opening ? progress + swing : progress - swing;
}

- (void)allowOvershoot {
    _overshoot = YES;
}

// Where the card's top is in the container: 9.1.90's player comes to rest on the card, not at the screen's foot.
- (CGFloat)cardTop {
    return _card.origin.y;
}

// 9.1.90's CompactOverlayTransition animates the player itself, so the morph follows where it is drawn.
- (void)follow {
    _follows = YES;
    _bar.hidden = YES;
}

- (instancetype)initWithContainer:(UIView *)container overlay:(UIView *)overlay bar:(UIView *)bar barRest:(CGRect)barRest {
    CGFloat radius = 0;
    CGRect card = SGRNowPlayingCardFrameIn(container, &radius);
    if (CGRectIsNull(card) || CGRectIsEmpty(card)) return nil;
    if (!(self = [super init])) return nil;
    _container = container;
    _overlay = overlay;
    _bar = bar;
    _barRest = barRest;
    _card = card;
    _cardRadius = radius;
    _barArtwork = SGRNowPlayingArtworkFrameIn(container);
    _spotifyAlpha = overlay.alpha;

    _sheet = [[UIView alloc] initWithFrame:card];
    _sheet.userInteractionEnabled = NO;
    _sheet.backgroundColor = SGRPlayerField().fieldColor ?: UIColor.blackColor;
    _sheet.layer.cornerCurve = kCACornerCurveContinuous;
    _sheet.clipsToBounds = YES;
    [container insertSubview:_sheet belowSubview:overlay];

    // The player's own paint is not a sublayer, so the content's transform would leave it where Spotify
    // put the player, a band below the sheet's top edge; the sheet paints instead.
    _overlayColor = CGColorRetain(overlay.layer.backgroundColor);
    overlay.layer.backgroundColor = NULL;

    _mask = [CALayer layer];
    _mask.backgroundColor = UIColor.blackColor.CGColor;
    _mask.cornerCurve = kCACornerCurveContinuous;
    overlay.layer.mask = _mask;

    if (bar.superview == container) [container bringSubviewToFront:bar];

    UIImage *artwork = SGRNowPlayingArtwork(NULL, NULL);
    if (artwork && !CGRectIsNull(_barArtwork)) {
        _cover = [[UIImageView alloc] initWithImage:artwork];
        _cover.userInteractionEnabled = NO;
        _cover.contentMode = UIViewContentModeScaleAspectFill;
        _cover.clipsToBounds = YES;
        _cover.layer.cornerCurve = kCACornerCurveContinuous;
        [container addSubview:_cover];
    }

    static NSUInteger logged;
    if (logged++ < 3) SGLog(@"player morph: card %@ r=%.0f, artwork %@, cover %@, screen r=%.0f", NSStringFromCGRect(card), radius,
                            NSStringFromCGRect(_barArtwork), _cover ? @"flown" : @"not flown", screenRadius());
    return self;
}

- (void)apply:(CGFloat)t {
    UIView *container = _container, *overlay = _overlay, *bar = _bar;
    if (!container || !overlay) return;
    // How far a spring has gone past either end, kept for the sheet's swell below; everything else reads t held to 0...1.
    CGFloat over = 0;
    if (_overshoot) over = MIN(0.3, t < 0 ? -t : (t > 1 ? t - 1 : 0));
    t = MIN(1, MAX(0, t));
    _lastT = t;
    _spotifyAlpha = overlay.alpha;
    _spotifyFrame = overlay.frame;

    if (_follows) {
        // Where Spotify's animation has the player now: its frame's model value is already the end.
        CALayer *drawn = overlay.layer.presentationLayer ?: overlay.layer;
        _spotifyFrame = drawn.frame;
    }
    CGRect full = container.bounds;
    CGRect sheet = lerpRect(_card, full, t);
    if (over > 0) {
        CGFloat swell = MIN(kPopLimit, over * kPopPoints);
        sheet = CGRectInset(sheet, -swell, -swell);
    }
    CGFloat radius = lerp(_cardRadius, screenRadius(), t);
    CGFloat scale = full.size.width > 0 ? sheet.size.width / full.size.width : 1;
    // The player's top goes to the sheet's: a mask clips nothing above the layer's bounds, so content
    // raised above Spotify's frame would show square corners. Spotify reads back only the player's
    // height (0x109815b4c, 0x109815c28), which stays.
    CGPoint origin = _follows ? _spotifyFrame.origin : CGPointMake(_spotifyFrame.origin.x, sheet.origin.y);
    CGSize size = overlay.bounds.size;
    CGPoint middle = CGPointMake(size.width / 2, size.height / 2);
    CGPoint target = CGPointMake(sheet.origin.x - origin.x, sheet.origin.y - origin.y);
    // A point q of the player lands at middle + scale * (q - middle) + shift; the top left at target.
    CGPoint shift = CGPointMake(target.x - middle.x + scale * middle.x, target.y - middle.y + scale * middle.y);

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [UIView performWithoutAnimation:^{
        overlay.layer.sublayerTransform = CATransform3DIdentity;
        if (!self->_follows) overlay.frame = (CGRect){origin, self->_spotifyFrame.size};
        CGRect coverInPlayer = SGRPlayerCoverFrameIn(overlay);

        overlay.layer.sublayerTransform = CATransform3DScale(CATransform3DMakeTranslation(shift.x, shift.y, 0), scale, scale, 1);
        self->_mask.frame = CGRectMake(target.x, target.y, sheet.size.width, sheet.size.height);
        self->_mask.cornerRadius = radius;
        if (!self->_follows) overlay.alpha = ramp(0.08, 0.55, t);

        self->_sheet.frame = sheet;
        self->_sheet.layer.cornerRadius = radius;
        self->_sheet.alpha = ramp(0, 0.15, t);

        // The card's top edge is the sheet's.
        CGFloat rise = sheet.origin.y - self->_card.origin.y;
        if (bar && !self->_follows) {
            CGRect frame = bar.frame;
            frame.origin.y = self->_barRest.origin.y + rise;
            bar.frame = frame;
            bar.alpha = 1 - ramp(0, 0.25, t);
        }

        if (self->_cover) {
            // Worked out relative to the sheet, so the cover stays on it the whole way rather than
            // heading for where the player's cover is while that is still below the screen.
            CGRect from = CGRectOffset(self->_barArtwork, -self->_card.origin.x, -self->_card.origin.y);
            if (CGRectIsNull(coverInPlayer)) {
                self->_cover.hidden = YES;
            } else {
                CGRect to = CGRectMake(middle.x + scale * (coverInPlayer.origin.x - middle.x) + shift.x + origin.x,
                                       middle.y + scale * (coverInPlayer.origin.y - middle.y) + shift.y + origin.y,
                                       coverInPlayer.size.width * scale, coverInPlayer.size.height * scale);
                self->_cover.hidden = NO;
                // The first open lays the cover out mid-way, so it is hidden once it is there.
                if (!self->_coverHidden) {
                    SGRPlayerSetCoverHidden(YES);
                    self->_coverHidden = YES;
                }
                to = CGRectOffset(to, -sheet.origin.x, -sheet.origin.y);
                self->_cover.frame = CGRectOffset(lerpRect(from, to, t), sheet.origin.x, sheet.origin.y);
                // The cover's corners are drawn under its paused shrink too.
                self->_cover.layer.cornerRadius = lerp(from.size.width / 2, SGRRadiusArtwork * SGRPlayerCoverScale() * scale, t);
                // Over an animated artwork the player's cover is hidden: the flown one fades out on the
                // way there instead of landing on an empty slot.
                self->_cover.alpha = SGRPlayerMotionShowing() ? 1 - ramp(0.6, 1, t) : 1;
            }
        }
    }];
    [CATransaction commit];
}

- (void)tearDown {
    UIView *overlay = _overlay;
    // 9.1.90, closing: the glass bar is put back under the sheet and the sheet and the flown cover fade into it,
    // rather than the dark card giving way to the glass in one frame.
    if (_follows && _lastT < 0.5) {
        UIView *sheet = _sheet, *cover = _cover;
        _sheet = nil;
        _cover = nil;
        _bar.hidden = NO;
        [UIView animateWithDuration:0.18 delay:0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                         animations:^{
            sheet.alpha = 0;
            cover.alpha = 0;
        } completion:^(BOOL finished) {
            [sheet removeFromSuperview];
            [cover removeFromSuperview];
        }];
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    overlay.layer.sublayerTransform = CATransform3DIdentity;
    if (overlay.layer.mask == _mask) overlay.layer.mask = nil;
    if (!_follows) overlay.alpha = _spotifyAlpha;
    if (overlay && !_follows) overlay.frame = _spotifyFrame;
    if (_follows) _bar.hidden = NO;
    if (!overlay.layer.backgroundColor) overlay.layer.backgroundColor = _overlayColor;
    CGColorRelease(_overlayColor);
    _overlayColor = NULL;
    [_sheet removeFromSuperview];
    [_cover removeFromSuperview];
    [CATransaction commit];
    if (_coverHidden) SGRPlayerSetCoverHidden(NO);
    _coverHidden = NO;
    _cover = nil;
}

@end

static char kMorphKey;

static SGRPlayerMorph *morphFor(SPTBarOverlayPresentationTransition *transition, BOOL create) {
    SGRPlayerMorph *morph = objc_getAssociatedObject(transition, &kMorphKey);
    if (morph || !create || SGRReduceMotion()) return morph;
    id<UIViewControllerContextTransitioning> context = [transition transitioningContext];
    UIView *container = context.containerView, *overlay = [transition overlayView];
    if (!container || !overlay || overlay.superview != container) return nil;
    if (container.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassRegular) return nil;
    morph = [[SGRPlayerMorph alloc] initWithContainer:container overlay:overlay bar:[transition barSnapshotView] barRest:[transition barFrame]];
    if (morph) {
        if (SGEnabled(SGRKeyMotionPlayer)) [morph allowOvershoot];
        objc_setAssociatedObject(transition, &kMorphKey, morph, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return morph;
}

%hook SPTBarOverlayPresentationTransition
- (void)setProgress:(double)progress {
    %orig;
    SGRPlayerMorph *morph = morphFor(self, YES);
    [morph apply:[morph bounced:[self progress]]];
    if (morph) [self tabBarSnapshotView].alpha = 0;
}

- (void)destroyTransitioningContext {
    SGRPlayerMorph *morph = morphFor(self, NO);
    if (morph) {
        [morph tearDown];
        objc_setAssociatedObject(self, &kMorphKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    %orig;
}
%end

#pragma mark - 9.1.90

// 9.1.90 presents the player with MainUI_TabBarUIImpl.CompactOverlayTransition, a UIKit animator that moves the
// player up from below the screen (animateTransition:, and startInteractiveTransition: for a drag) with its own
// stand-ins (npbSnapshotView, tabBarSnapshotView; BarTransition.x). A display link reads how far up Spotify's animation
// has the player and morphs to match, so Spotify's frame, alpha and completion stay its own. It is let go once the
// transition is no longer interactive and the player has no animation left and holds still a few frames.
static const CFTimeInterval kGiveUp = 0.9;   // UIKit's presentation runs about 0.5 s

@interface SGRMorphFollower : NSObject
@property (nonatomic, strong) SGRPlayerMorph *morph;
@property (nonatomic, weak) UIView *container, *overlay;
@property (nonatomic, weak) id<UIViewControllerContextTransitioning> context;
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic) NSInteger still;
@property (nonatomic) CGFloat lastY;
@property (nonatomic) CFTimeInterval settledSince;   // when it was last driven by a finger, or began
// The mod's own spring, for a transition that starts in nobody's hand (a tap on the bar, the close button): the sheet
// takes its progress from the spring rather than from where Spotify has put the player, which is only read to know the
// transition is still running. A finger on the player puts it back to following that.
@property (nonatomic) BOOL spring, open;
@property (nonatomic) CFTimeInterval started, duration, giveUp;
@property (nonatomic) CGFloat damping;
@end

@implementation SGRMorphFollower
- (void)tick:(CADisplayLink *)link {
    UIView *container = self.container, *overlay = self.overlay;
    if (!container || !overlay || !overlay.window) {
        [self finish];
        return;
    }
    CALayer *drawn = overlay.layer.presentationLayer ?: overlay.layer;
    // 1 with the player's top at the screen's, 0 with it at the card's: Spotify brings the player to rest there when
    // it closes, short of the screen's foot, so a progress over the whole height left the sheet a sixth of the way
    // open when Spotify was done, and it went in one frame (screen recording, 2026-10-11).
    CGFloat y = drawn.frame.origin.y, rest = self.morph.cardTop;
    if (rest <= 0) rest = container.bounds.size.height;
    BOOL interactive = self.context.isInteractive;
    CFTimeInterval now = CACurrentMediaTime();
    CGFloat progress = rest > 0 ? 1 - y / rest : 1;
    BOOL springing = self.spring && !interactive && now - self.started < self.duration;
    if (self.spring && !interactive) {
        CGFloat step = springStep(now - self.started, self.duration, self.damping);
        progress = self.open ? step : 1 - step;
    }
    [self.morph apply:progress];
    BOOL moving = overlay.layer.animationKeys.count > 0 || fabs(y - self.lastY) > 0.5 || interactive;
    self.lastY = y;
    self.still = moving ? 0 : self.still + 1;
    // Let go once still (and the spring has run its course), or giveUp after a finger last drove it whatever the layer
    // holds: a mask and a transform left on the player would keep its glass buttons from drawing. A transition Spotify
    // finishes first takes the player off the screen, which lets go at once.
    if (interactive || !self.settledSince) self.settledSince = now;
    if ((self.still >= 3 && !springing) || now - self.settledSince > (self.giveUp > 0 ? self.giveUp : kGiveUp)) [self finish];
}
- (void)finish {
    if (!self.link) return;
    static NSUInteger logged;
    if (logged++ < 3) SGLog(@"player morph: let go after %.2f s, %@", CACurrentMediaTime() - self.settledSince, self.still >= 3 ? @"settled" : @"given up");
    [self.link invalidate];
    self.link = nil;
    [self.morph tearDown];
    self.morph = nil;
}
@end

static id ivarOf(id object, const char *name) {
    Ivar ivar = class_getInstanceVariable(object_getClass(object), name);
    return ivar ? object_getIvar(object, ivar) : nil;
}

static char kFollowerKey;

static void followTransition(id transition, id<UIViewControllerContextTransitioning> context) {
    if (SGRReduceMotion() || !context) return;
    UIView *container = context.containerView;
    if (container.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassRegular) return;
    UIViewController *to = [context viewControllerForKey:UITransitionContextToViewControllerKey];
    UIView *overlay = to.isBeingPresented ? [context viewForKey:UITransitionContextToViewKey] : [context viewForKey:UITransitionContextFromViewKey];
    if (!overlay || overlay.superview != container) return;
    SGRMorphFollower *old = objc_getAssociatedObject(transition, &kFollowerKey);
    [old finish];
    SGRPlayerMorph *morph = [[SGRPlayerMorph alloc] initWithContainer:container overlay:overlay bar:ivarOf(transition, "npbSnapshotView") barRest:CGRectZero];
    if (!morph) return;
    [morph follow];
    ((UIView *)ivarOf(transition, "tabBarSnapshotView")).alpha = 0;
    SGRMorphFollower *follower = [SGRMorphFollower new];
    follower.morph = morph;
    follower.container = container;
    follower.overlay = overlay;
    follower.context = context;
    follower.lastY = CGFLOAT_MAX;
    // A transition nobody is dragging runs on the mod's spring, as long as Spotify says it will take: it ends when
    // Spotify's does, so the spring is over a little before that. Bounce and Speed are the Motion sliders.
    if (!context.isInteractive && SGEnabled(SGRKeyMotionPlayer)) {
        NSTimeInterval declared = [(id<UIViewControllerAnimatedTransitioning>)transition transitionDuration:context];
        follower.duration = declared > 0.15 ? declared * 0.95 : 0.5;
        follower.damping = playerDamping();
        follower.open = to.isBeingPresented;
        follower.started = CACurrentMediaTime();
        follower.giveUp = MAX(kGiveUp, follower.duration + 0.3);
        follower.spring = YES;
        [morph allowOvershoot];
    }
    follower.link = [CADisplayLink displayLinkWithTarget:follower selector:@selector(tick:)];
    follower.link.preferredFrameRateRange = CAFrameRateRangeMake(80, 120, 120);
    [follower.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    objc_setAssociatedObject(transition, &kFollowerKey, follower, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [follower tick:follower.link];
    static NSUInteger logged;
    if (logged++ < 3) SGLog(@"player morph: follows CompactOverlayTransition (%@)", to.isBeingPresented ? @"open" : @"close");
}

%hook _TtC19MainUI_TabBarUIImpl24CompactOverlayTransition
// The Speed slider stretches (or shortens) the player's open and close; Spotify's animator takes how long it runs
// from here if it asks, and the mod's spring takes it from here either way.
- (NSTimeInterval)transitionDuration:(id<UIViewControllerContextTransitioning>)context {
    NSTimeInterval duration = %orig;
    if (SGRReduceMotion() || !SGEnabled(SGRKeyMotionPlayer)) return duration;
    return duration * 100.0 / (double)SGRMotionSpeed();
}

- (void)animateTransition:(id<UIViewControllerContextTransitioning>)context {
    %orig;
    followTransition(self, context);
}
- (void)startInteractiveTransition:(id<UIViewControllerContextTransitioning>)context {
    %orig;
    followTransition(self, context);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"SPTBarOverlayPresentationTransition"]);
}
