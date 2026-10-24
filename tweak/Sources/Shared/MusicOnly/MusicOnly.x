// Music only, the library: a row or card of Your Library that is a podcast, a show or an audiobook closes up. Its kind is
// the line under the title ("Podcast • name", "Audiobook • author"), or the id of the row (Podcast.Row.Library). The cell is
// measured at no height and its content made clear, so the list closes up around it, and a cell reused for a song's
// playlist is made whole again.
//
// Tree (trees/clean/library/03.txt:30-73): YourLibrarySwipeableCollectionViewCellContainer holds the row, whose
// id says Playlist, Album or Podcast, and whose labels are the title and the kind.
#import "Core/SGCore.h"
#import "MusicOnly.h"

static BOOL kindIsNotMusic(NSString *text) {
    for (NSString *kind in @[@"Podcast", @"Show", @"Audiobook", @"Episode"]) {
        if ([text hasPrefix:[kind stringByAppendingString:@" •"]] || [text isEqualToString:kind]) return YES;
    }
    return NO;
}

static BOOL notMusic(UIView *cell) {
    __block BOOL found = NO;
    SGForEachView(cell, ^(UIView *v) {
        if (found) return;
        NSString *identifier = v.accessibilityIdentifier;
        if ([identifier hasPrefix:@"Podcast."] || [identifier hasPrefix:@"Audiobook."] || [identifier hasPrefix:@"Show."] || [identifier hasPrefix:@"Episode."]) found = YES;
        else if ([v isKindOfClass:UILabel.class] && kindIsNotMusic(((UILabel *)v).text)) found = YES;
    });
    return found;
}

%hook _TtC21YourLibrary_CommonKit47YourLibrarySwipeableCollectionViewCellContainer
- (UICollectionViewLayoutAttributes *)preferredLayoutAttributesFittingAttributes:(UICollectionViewLayoutAttributes *)attributes {
    UICollectionViewLayoutAttributes *result = %orig;
    UICollectionViewCell *cell = (UICollectionViewCell *)self;
    BOOL hide = notMusic(cell.contentView);
    cell.contentView.alpha = hide ? 0 : 1;
    cell.userInteractionEnabled = !hide;
    if (hide) result.size = CGSizeMake(result.size.width, 0);
    return result;
}
%end

%ctor {
    if (!SGFlag(SGKeyMusicOnly, NO)) return;
    %init;
    SGRequireClasses(@[@"_TtC21YourLibrary_CommonKit47YourLibrarySwipeableCollectionViewCellContainer"]);
}
