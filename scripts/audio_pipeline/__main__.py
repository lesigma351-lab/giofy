"""
CLI entry point for scripts.audio_pipeline module.
"""

import argparse
import sys
from pathlib import Path

from .organizer import scan_and_ingest
from .watcher import watch_directory

DEFAULT_DESTINATION = Path.home() / "Music" / "SpotifyLocal"


def main():
    parser = argparse.ArgumentParser(
        description="Local media ingestion and filename sanitization pipeline for Spotify Local Files."
    )
    parser.add_argument(
        "--source",
        "-s",
        type=Path,
        required=True,
        help="Source directory where incoming audio files land (e.g. ~/Downloads/IncomingAudio)",
    )
    parser.add_argument(
        "--destination",
        "-d",
        type=Path,
        default=DEFAULT_DESTINATION,
        help=f"Target playback directory (default: {DEFAULT_DESTINATION})",
    )
    parser.add_argument(
        "--copy",
        action="store_true",
        help="Copy files instead of moving them",
    )
    parser.add_argument(
        "--watch",
        "-w",
        action="store_true",
        help="Run continuously and monitor the source directory for new files",
    )
    parser.add_argument(
        "--interval",
        type=float,
        default=3.0,
        help="Polling interval in seconds when using --watch (default: 3.0)",
    )

    args = parser.parse_args()

    source = args.source.expanduser().resolve()
    destination = args.destination.expanduser().resolve()

    if args.watch:
        watch_directory(
            source_dir=source,
            destination_dir=destination,
            interval_seconds=args.interval,
            copy_only=args.copy,
        )
    else:
        results = scan_and_ingest(
            source_dir=source,
            destination_dir=destination,
            copy_only=args.copy,
        )
        print(f"\nDone. Processed {len(results)} audio track(s).")


if __name__ == "__main__":
    main()
