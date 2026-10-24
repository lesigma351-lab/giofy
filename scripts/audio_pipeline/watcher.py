"""
Directory monitor for continuous ingestion of incoming audio files into Spotify Local Files.
"""

import time
from pathlib import Path
from typing import Dict

from .organizer import SUPPORTED_EXTENSIONS, process_audio_file


def watch_directory(
    source_dir: Path,
    destination_dir: Path,
    interval_seconds: float = 3.0,
    copy_only: bool = False,
):
    """
    Monitors source_dir for incoming audio files and transfers them to destination_dir.
    Waits for files to finish downloading/writing before processing.
    """
    print(f"[*] Monitoring source directory: {source_dir}")
    print(f"[*] Destination routing: {destination_dir}")
    print(f"[*] Poll interval: {interval_seconds}s (Press Ctrl+C to stop)\n")

    known_sizes: Dict[Path, int] = {}

    try:
        while True:
            if source_dir.exists():
                current_files = [
                    f for f in source_dir.iterdir()
                    if f.is_file() and f.suffix.lower() in SUPPORTED_EXTENSIONS
                ]

                for file_path in current_files:
                    try:
                        current_size = file_path.stat().st_size
                    except FileNotFoundError:
                        continue

                    # If file is still being written to, wait until size stabilizes
                    last_size = known_sizes.get(file_path)
                    if last_size is None or last_size != current_size:
                        known_sizes[file_path] = current_size
                        continue

                    # File size is stable: ingest it
                    result = process_audio_file(file_path, destination_dir, copy_only=copy_only)
                    if result:
                        action = "Copied" if copy_only else "Moved"
                        print(f"[{action}] {file_path.name} -> {result.name}")
                    known_sizes.pop(file_path, None)

            time.sleep(interval_seconds)
    except KeyboardInterrupt:
        print("\n[*] Monitoring stopped.")
