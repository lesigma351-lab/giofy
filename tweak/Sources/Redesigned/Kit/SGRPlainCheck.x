// Plain checkmark (Appearance): Spotify's circled tick on a saved song swapped for a plain checkmark in the accent.
//
// The Add button (id=Components.UI.AddToButton, a UIButton) draws its state with a Lottie animation in a
// StateMicroInteractionView<AddToButtonState> (trees: player 1434-1436, the rows' buttons the same): a plus when the
// song is not saved, an accent circle with a tick when it is. Spotify marks a saved song's button selected ("Added to
// playlist"), so the button's own selected state tells which. Saved, the animation goes transparent and a checkmark of
// the Kit's stands in its place; not saved, Spotify's plus shows as it is.
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "SGRKit.h"

static const CGFloat kCheckSize = 19;
static char kCheckKey, kAnimationKey;

BOOL SGRPlainCheckOn(void) {
    static BOOL on;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ on = SGHidden(SGRKeyPlainCheck); });
    return on;
}

static UIView *animationIn(UIButton *button) {
    UIView *found = objc_getAssociatedObject(button, &kAnimationKey);
    if (found.superview) return found;
    static Class lottie;
    if (!lottie) lottie = NSClassFromString(@"Lottie.LottieAnimationView");
    found = nil;
    for (UIView *child in button.subviews) {
        for (UIView *inner in child.subviews) {
            if (lottie && [inner isKindOfClass:lottie]) found = inner;
        }
    }
    objc_setAssociatedObject(button, &kAnimationKey, found, OBJC_ASSOCIATION_ASSIGN);
    return found;
}

// The player's like (Apple Music icons on, Player settings): both of its states are the mod's glyph, a plus and a tick, since
// Spotify's unsaved plus is drawn mid-animation as an asterisk in a circle on some phones. The key is Player.h's own.
static NSString *const kAppleIconsKey = @"spotifyglass.redesign.player.appleIcons";

static BOOL inPlayer(UIView *view) {
    NSUInteger depth = 0;
    for (UIView *up = view.superview; up && depth < 12; up = up.superview, depth++) {
        if ([up.accessibilityIdentifier isEqualToString:@"npv.bottomStackView"]) return YES;
    }
    return NO;
}

static void showState(UIButton *button) {
    UIView *animation = animationIn(button);
    if (!animation) return;
    BOOL player = SGEnabled(kAppleIconsKey) && inPlayer(button);
    BOOL saved = button.isSelected;
    BOOL replaced = player || (saved && SGRPlainCheckOn());
    UIImageView *check = objc_getAssociatedObject(button, &kCheckKey);
    BOOL popped = NO;
    if (replaced && !check) {
        check = [UIImageView new];
        check.accessibilityIdentifier = SGRPlainCheckIdentifier;
        check.contentMode = UIViewContentModeCenter;
        check.userInteractionEnabled = NO;
        check.isAccessibilityElement = NO;
        objc_setAssociatedObject(button, &kCheckKey, check, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (check && replaced) {
        UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:saved ? kCheckSize : 26 weight:saved ? UIImageSymbolWeightBold : UIImageSymbolWeightRegular];
        NSString *name = saved ? @"checkmark" : @"plus.circle";
        NSString *before = objc_getAssociatedObject(check, &kCheckKey);
        if (![before isEqual:name]) {
            objc_setAssociatedObject(check, &kCheckKey, name, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            check.image = [UIImage systemImageNamed:name withConfiguration:configuration];
            // A save or an unsave pops the new glyph in on the spring, as the Music app's does.
            popped = before != nil && check.window && !SGRReduceMotion();
        }
        check.tintColor = saved ? SGRAccent() : [UIColor colorWithWhite:1 alpha:0.9];
    }
    if (check && check.superview != button) [button addSubview:check];
    check.frame = button.bounds;
    check.alpha = replaced ? 1 : 0;
    // Alpha, not hidden: Lottie's own state keeps running under it. The layer goes out of sight as well, which Spotify
    // does not reset the way it resets the alpha.
    animation.alpha = replaced ? 0 : 1;
    animation.layer.hidden = replaced;
    if (popped) {
        check.transform = CGAffineTransformMakeScale(0.4, 0.4);
        check.alpha = 0;
        SGRAnimate(SGRMotionRespond, ^{
            check.transform = CGAffineTransformIdentity;
            check.alpha = 1;
        }, nil);
    }
}

%hook UIButton
- (void)layoutSubviews {
    %orig;
    if ([self.accessibilityIdentifier isEqualToString:@"Components.UI.AddToButton"]) showState(self);
}

- (void)setSelected:(BOOL)selected {
    %orig;
    if ([self.accessibilityIdentifier isEqualToString:@"Components.UI.AddToButton"]) showState(self);
}
%end

%ctor {
    if (!SGRedesignedUI() || !(SGRPlainCheckOn() || SGEnabled(kAppleIconsKey))) return;
    %init;
}
