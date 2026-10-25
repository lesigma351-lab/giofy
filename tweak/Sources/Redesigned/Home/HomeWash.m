// Home redesign: a wash of color behind the top of the page, taken from the Top picks cover in view and sliding to the next
// one's as the shelf is swiped (a glow like the one Apple Music and Chroma put behind their top cards).
//
// The wash is one gradient layer at the bottom of the page's scroll view, so it scrolls away with the content, from well above
// the header (for the overscroll) down to kWashDepth. The page and the views from the Top picks shelf up to the page paint clear
// so it shows round the cards. The color is read off the cards (HomeTopPickCard.m): the card whose leading edge is nearest the
// shelf's own, blended with the next by how far the shelf has moved between them.
//
// What the shelf scrolls is the shelf itself or a scroll view inside it (a compositional section that scrolls across), so
// the scroll view the card is in is the one watched, by its contentOffset (KVO). One scroll view is watched at a time and
// held strongly, so it never goes away with the observer still on it.
// Threading: main thread only.
#import <QuartzCore/QuartzCore.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Home.h"

// How far the wash reaches down the page from its top, and how far up it reaches for the rubber band of an overscroll.
static const CGFloat kWashAbove = 900;

// How far down the page the wash reaches (the Wash depth setting) and its strength (0 to 1).
static CGFloat washDepth(void) {
    return MAX(300, MIN(1000, SGInt(SGRKeyHomeWashDepth, 620)));
}

static CGFloat washStrength(void) {
    return MAX(0, MIN(100, SGInt(SGRKeyHomeWashStrength, 95))) / 100.0;
}
// Where the shelf's leading card sits from the shelf's edge.
static const CGFloat kLead = 20;

static void *kContext = &kContext;

@interface SGRHomeWash : NSObject
+ (instancetype)shared;
- (void)watch:(UIView *)card;
@end

@implementation SGRHomeWash {
    UIScrollView *_paging;
    __weak UIScrollView *_page;
    CAGradientLayer *_wash;
    UIColor *_color;
}

+ (instancetype)shared {
    static SGRHomeWash *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [SGRHomeWash new]; });
    return shared;
}

static UIScrollView *scrollAbove(UIView *view) {
    for (UIView *v = view.superview; v; v = v.superview) {
        if ([v isKindOfClass:UIScrollView.class]) return (UIScrollView *)v;
    }
    return nil;
}

static void clear(UIView *view) {
    if (view.backgroundColor && CGColorGetAlpha(view.backgroundColor.CGColor) > 0) view.backgroundColor = nil;
    if (view.layer.backgroundColor && CGColorGetAlpha(view.layer.backgroundColor) > 0) view.layer.backgroundColor = NULL;
}

- (void)watch:(UIView *)card {
    UICollectionView *shelf = SGRHomeTopPicksShelfAround(card);
    UIScrollView *paging = scrollAbove(card);
    UIScrollView *page = scrollAbove(shelf);
    if (!shelf || !paging || !page) return;
    // Clear from the shelf up to the page so the wash shows round the cards.
    for (UIView *v = shelf; v && v != page; v = v.superview) clear(v);
    clear(page);
    if (_page != page || !_wash) {
        [_wash removeFromSuperlayer];
        _wash = [CAGradientLayer layer];
        _wash.startPoint = CGPointMake(0.5, 0);
        _wash.endPoint = CGPointMake(0.5, 1);
        _wash.locations = @[@0, @0.4, @1];
        _color = nil;
        _page = page;
        [page.layer insertSublayer:_wash atIndex:0];
    }
    CGFloat top = -(page.adjustedContentInset.top + kWashAbove), depth = washDepth();
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _wash.frame = CGRectMake(0, top, page.bounds.size.width, depth - top);
    // Solid from the top of the layer to the screen's top, so an overscroll pulls down into the same color.
    CGFloat height = depth - top, zero = -top / height;
    _wash.locations = @[@0, @(zero), @(zero + 0.45 * depth / height), @1];
    [CATransaction commit];
    if (_paging != paging) {
        if (_paging) [_paging removeObserver:self forKeyPath:@"contentOffset" context:kContext];
        _paging = paging;
        [_paging addObserver:self forKeyPath:@"contentOffset" options:0 context:kContext];
    }
    [self update];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context != kContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    [self update];
}

static UIColor *blend(UIColor *a, UIColor *b, CGFloat t) {
    CGFloat ar = 0, ag = 0, ab = 0, br = 0, bg = 0, bb = 0, alpha = 1;
    if (![a getRed:&ar green:&ag blue:&ab alpha:&alpha] || ![b getRed:&br green:&bg blue:&bb alpha:&alpha]) return a;
    return [UIColor colorWithRed:ar + (br - ar) * t green:ag + (bg - ag) * t blue:ab + (bb - ab) * t alpha:1];
}

- (void)update {
    UIScrollView *paging = _paging;
    if (!paging || !_wash || !paging.window) return;
    // The cards of the shelf in order across the screen, each with its x in the window.
    NSMutableArray<UIView *> *cards = [NSMutableArray array];
    SGForEachView(paging, ^(UIView *v) {
        if ([v.accessibilityIdentifier isEqualToString:@"Components.UI.HomeCard"]) [cards addObject:v];
    });
    CGFloat edge = [paging.superview convertPoint:paging.frame.origin toView:nil].x + kLead;
    NSMutableArray<NSNumber *> *xs = [NSMutableArray array];
    for (UIView *card in cards) [xs addObject:@([card.superview convertPoint:card.frame.origin toView:nil].x)];
    NSInteger before = -1, after = -1;
    for (NSInteger i = 0; i < (NSInteger)cards.count; i++) {
        CGFloat x = xs[i].doubleValue;
        if (x <= edge + 0.5 && (before < 0 || x > xs[before].doubleValue)) before = i;
        if (x > edge + 0.5 && (after < 0 || x < xs[after].doubleValue)) after = i;
    }
    UIColor *a = before >= 0 ? SGRHomeTopPickColor(cards[before]) : nil;
    UIColor *b = after >= 0 ? SGRHomeTopPickColor(cards[after]) : nil;
    UIColor *color = a && b ? blend(a, b, MIN(1, MAX(0, (edge - xs[before].doubleValue) / (xs[after].doubleValue - xs[before].doubleValue)))) : (a ?: b);
    if (!color) return;
    // A little more vivid than the card, since it fades into black.
    color = SGRHomeVivid(color, 1.25);
    if (_color && CGColorEqualToColor(_color.CGColor, color.CGColor)) return;
    _color = color;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _wash.colors = @[(id)[color colorWithAlphaComponent:washStrength()].CGColor, (id)[color colorWithAlphaComponent:washStrength()].CGColor,
                    (id)[color colorWithAlphaComponent:0.47 * washStrength()].CGColor, (id)[color colorWithAlphaComponent:0].CGColor];
    [CATransaction commit];
}
@end

void SGRHomeWashWatch(UIView *card) {
    if (!SGEnabled(SGRKeyHomeWash)) return;
    [[SGRHomeWash shared] watch:card];
}
