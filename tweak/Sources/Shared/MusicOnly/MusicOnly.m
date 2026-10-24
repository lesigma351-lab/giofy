#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "MusicOnly.h"

BOOL SGIsNonMusicURI(NSString *uri) {
    return [uri containsString:@"spotify:episode:"] || [uri containsString:@"spotify:chapter:"] ||
           [uri containsString:@"spotify:show:"] || [uri containsString:@"spotify:audiobook:"] ||
           [uri containsString:@"/episode/"] || [uri containsString:@"/chapter/"];
}

SGModRow *SGMusicOnlyRow(void) {
    return SGWithTile(SGOptionRow(@"Music only", @"No podcasts, shows or audiobooks: they are skipped when they play and gone from your library. Restart to apply.", SGKeyMusicOnly),
                      @"music.note", UIColor.systemGreenColor);
}
