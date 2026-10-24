// Music only: no podcasts, shows, episodes or audiobooks. What plays is held to music (ArtistSkip.x skips an episode or an
// audiobook chapter the moment the player reaches it) and the rows of Your Library that are one of them close up
// (MusicOnly.x). Works under either look. Off until switched on; the rows are read at launch, so a change needs a restart.
#import <UIKit/UIKit.h>
@class SGModRow;

#define SGKeyMusicOnly @"spotifyglass.musicOnly"

// Whether a track URI is a podcast episode or an audiobook chapter, so not music.
BOOL SGIsNonMusicURI(NSString *uri);
// The switch's row for Mod Settings' main page.
SGModRow *SGMusicOnlyRow(void);
