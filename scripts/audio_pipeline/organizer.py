"""
Core audio file ingestion, sanitization, and routing logic for Spotify Local Files.
"""

import os
import re
import shutil
import unicodedata
from pathlib import Path
from typing import List, Optional

# Supported audio extensions recognized by Spotify Local Files
SUPPORTED_EXTENSIONS = {".mp3", ".m4a", ".flac", ".wav", ".aac", ".ogg"}

# Prohibited or troublesome filesystem characters
INVALID_FILENAME_CHARS = re.compile(r'[\\/*?:"<>|]')


def sanitize_filename(filename: str) -> str:
    """
    Sanitizes a filename:
    - Normalizes unicode characters (NFKD).
    - Removes illegal filesystem characters.
    - Cleans up duplicate spaces, underscores, and common clutter.
    - Strips leading/trailing whitespace and punctuation.
    """
    path = Path(filename)
    stem = path.stem
    ext = path.suffix.lower()

    # Normalize unicode
    normalized = unicodedata.normalize("NFKD", stem)

    # Strip illegal characters
    cleaned = INVALID_FILENAME_CHARS.sub("", normalized)

    # Clean up redundant spaces and symbols
    cleaned = re.sub(r"\s+", " ", cleaned)
    cleaned = re.sub(r"_+", "_", cleaned)
    cleaned = cleaned.strip(" .-_")

    if not cleaned:
        cleaned = "unnamed_track"

    return f"{cleaned}{ext}"


def get_unique_destination(destination_dir: Path, target_filename: str) -> Path:
    """
    Ensures existing files are never overwritten by appending an incremental counter.
    """
    dest_path = destination_dir / target_filename
    if not dest_path.exists():
        return dest_path

    target_path = Path(target_filename)
    stem = target_path.stem
    ext = target_path.suffix

    counter = 1
    while dest_path.exists():
        dest_path = destination_dir / f"{stem} ({counter}){ext}"
        counter += 1

    return dest_path


def process_audio_file(
    file_path: Path,
    destination_dir: Path,
    copy_only: bool = False,
) -> Optional[Path]:
    """
    Validates, sanitizes, and transfers an audio file to destination_dir.
    Returns destination Path if successful, None otherwise.
    """
    if not file_path.is_file():
        return None

    if file_path.suffix.lower() not in SUPPORTED_EXTENSIONS:
        return None

    destination_dir.mkdir(parents=True, exist_ok=True)

    sanitized_name = sanitize_filename(file_path.name)
    target_path = get_unique_destination(destination_dir, sanitized_name)

    try:
        if copy_only:
            shutil.copy2(file_path, target_path)
        else:
            shutil.move(str(file_path), str(target_path))
        return target_path
    except (IOError, OSError) as err:
        print(f"[Error] Failed to process {file_path.name}: {err}")
        return None


def scan_and_ingest(
    source_dir: Path,
    destination_dir: Path,
    copy_only: bool = False,
) -> List[Path]:
    """
    Scans source_dir and transfers all supported audio files to destination_dir.
    """
    processed_files: List[Path] = []

    if not source_dir.exists() or not source_dir.is_dir():
        print(f"[Error] Source directory '{source_dir}' does not exist.")
        return processed_files

    for entry in sorted(source_dir.iterdir()):
        if entry.is_file() and entry.suffix.lower() in SUPPORTED_EXTENSIONS:
            result = process_audio_file(entry, destination_dir, copy_only=copy_only)
            if result:
                processed_files.append(result)
                action = "Copied" if copy_only else "Moved"
                print(f"[{action}] '{entry.name}' -> '{result.name}'")

    return processed_files
