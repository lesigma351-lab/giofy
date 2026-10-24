// Home redesign: the Top picks cards first, above the shortcuts, the way the Music app opens on its Top Picks.
//
// Spotify's feed orders the sections, and the shortcuts come first. The order is not touched: the page's layout is asked where
// each section is and answers with the Top picks section moved to the top of the page and what was above it moved down by its
// height, so the page is the same height and a section below is where it was. Taps, self sizing and scrolling go by the layout's
// answers, so a section is where it is drawn and the cells that are made are the ones on screen.
//
// The page's layout is not a class of the mod's: once the Top picks section has been found (HomeTopPicks.x), its layout's class
// is given an answer of its own for -layoutAttributesForElementsInRect: and -layoutAttributesForItemAtIndexPath:, which
// asks the original for every item and moves what has to move. Only a layout the shelf was found in (marked here) takes the
// change; other layouts of the same class pass through.
// Threading: main thread only.
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Home.h"

static char kPageKey, kTopKey;
// Set while the original is asked for everything: it may ask the other method itself, which must not start over.
static _Thread_local BOOL sAsking;
static NSMutableDictionary<NSString *, NSValue *> *sOriginals;

static NSString *keyFor(Class cls, SEL sel) {
    return [NSString stringWithFormat:@"%p:%s", (__bridge void *)cls, sel_getName(sel)];
}

static IMP originalOf(Class cls, SEL sel) {
    for (Class c = cls; c; c = class_getSuperclass(c)) {
        NSValue *value = sOriginals[keyFor(c, sel)];
        if (value) return (IMP)value.pointerValue;
    }
    return NULL;
}

typedef NSArray<UICollectionViewLayoutAttributes *> *(*RectFn)(id, SEL, CGRect);
typedef UICollectionViewLayoutAttributes *(*ItemFn)(id, SEL, NSIndexPath *);

static BOOL isCell(UICollectionViewLayoutAttributes *a) {
    return a.representedElementCategory == UICollectionElementCategoryCell;
}

// Every attribute of the layout, as the original has them.
static NSArray<UICollectionViewLayoutAttributes *> *everything(UICollectionViewLayout *layout) {
    RectFn orig = (RectFn)originalOf(object_getClass(layout), @selector(layoutAttributesForElementsInRect:));
    if (!orig) return @[];
    CGFloat height = layout.collectionView.contentSize.height + 4000;
    BOOL was = sAsking;
    sAsking = YES;
    NSArray *all = orig(layout, @selector(layoutAttributesForElementsInRect:), CGRectMake(-1000, -2000, 10000, height));
    sAsking = was;
    return all ?: @[];
}

// The attributes with the Top picks cell moved to the top of the page and what was above it down by its height; the same
// objects when nothing moves.
static NSArray<UICollectionViewLayoutAttributes *> *reordered(NSArray<UICollectionViewLayoutAttributes *> *all) {
    NSInteger top = SGRHomeTopPicksIndex();
    if (top == NSIntegerMax) return all;
    UICollectionViewLayoutAttributes *topAttributes = nil;
    CGFloat firstY = CGFLOAT_MAX;
    for (UICollectionViewLayoutAttributes *a in all) {
        if (!isCell(a)) continue;
        firstY = MIN(firstY, a.frame.origin.y);
        if (a.indexPath.section * 10000 + a.indexPath.item == top) topAttributes = a;
    }
    if (!topAttributes || topAttributes.frame.origin.y <= firstY + 0.5) return all;
    CGFloat topY = topAttributes.frame.origin.y, endAbove = firstY;
    for (UICollectionViewLayoutAttributes *a in all) {
        if (isCell(a) && a != topAttributes && a.frame.origin.y >= firstY - 0.5 && a.frame.origin.y < topY - 0.5) endAbove = MAX(endAbove, CGRectGetMaxY(a.frame));
    }
    CGFloat shift = topAttributes.frame.size.height + (topY - endAbove);
    NSMutableArray *moved = [NSMutableArray arrayWithCapacity:all.count];
    for (UICollectionViewLayoutAttributes *a in all) {
        if (!isCell(a)) {
            [moved addObject:a];
            continue;
        }
        UICollectionViewLayoutAttributes *copy = [a copy];
        CGRect frame = a.frame;
        if (a == topAttributes) frame.origin.y = firstY;
        else if (a.frame.origin.y >= firstY - 0.5 && a.frame.origin.y < topY - 0.5) frame.origin.y += shift;
        copy.frame = frame;
        [moved addObject:copy];
    }
    return moved;
}

static void hookClass(Class cls) {
    if (!sOriginals) sOriginals = [NSMutableDictionary dictionary];
    SEL rect = @selector(layoutAttributesForElementsInRect:), item = @selector(layoutAttributesForItemAtIndexPath:);
    if (sOriginals[keyFor(cls, rect)]) return;
    Method rectMethod = class_getInstanceMethod(cls, rect), itemMethod = class_getInstanceMethod(cls, item);
    if (!rectMethod || !itemMethod) return;
    sOriginals[keyFor(cls, rect)] = [NSValue valueWithPointer:(void *)method_getImplementation(rectMethod)];
    sOriginals[keyFor(cls, item)] = [NSValue valueWithPointer:(void *)method_getImplementation(itemMethod)];
    class_replaceMethod(cls, rect, imp_implementationWithBlock(^NSArray *(UICollectionViewLayout *self_, CGRect area) {
        RectFn orig = (RectFn)originalOf(object_getClass(self_), rect);
        if (sAsking || !objc_getAssociatedObject(self_, &kPageKey)) return orig(self_, rect, area);
        NSMutableArray *inside = [NSMutableArray array];
        for (UICollectionViewLayoutAttributes *a in reordered(everything(self_))) {
            if (CGRectIntersectsRect(a.frame, area)) [inside addObject:a];
        }
        return inside;
    }), method_getTypeEncoding(rectMethod));
    class_replaceMethod(cls, item, imp_implementationWithBlock(^UICollectionViewLayoutAttributes *(UICollectionViewLayout *self_, NSIndexPath *path) {
        ItemFn orig = (ItemFn)originalOf(object_getClass(self_), item);
        UICollectionViewLayoutAttributes *own = orig(self_, item, path);
        if (sAsking || !own || !isCell(own) || !objc_getAssociatedObject(self_, &kPageKey)) return own;
        for (UICollectionViewLayoutAttributes *a in reordered(everything(self_))) {
            if (isCell(a) && [a.indexPath isEqual:path]) return a;
        }
        return own;
    }), method_getTypeEncoding(itemMethod));
}

void SGRHomeOrderWatch(UIView *shelf) {
    if (!SGEnabled(SGRKeyHomeCardsFirst)) return;
    UICollectionView *page = nil;
    for (UIView *v = shelf.superview; v; v = v.superview) {
        if ([v isKindOfClass:UICollectionView.class]) {
            page = (UICollectionView *)v;
            break;
        }
    }
    UICollectionViewLayout *layout = page.collectionViewLayout;
    if (!layout) return;
    NSNumber *seen = objc_getAssociatedObject(layout, &kTopKey);
    NSInteger top = SGRHomeTopPicksIndex();
    if (seen && seen.integerValue == top) return;
    objc_setAssociatedObject(layout, &kTopKey, @(top), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!objc_getAssociatedObject(layout, &kPageKey)) {
        hookClass(object_getClass(layout));
        objc_setAssociatedObject(layout, &kPageKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SGLog(@"redesign home: cards first, page layout %@", NSStringFromClass(object_getClass(layout)));
    }
    __weak UICollectionViewLayout *weakLayout = layout;
    dispatch_async(dispatch_get_main_queue(), ^{ [weakLayout invalidateLayout]; });
}
