# Local Audio Pipeline

`scripts/organize-local-audio.py` provides an automated ingestion and sanitization pipeline for organizing local audio tracks into Spotify's local files directory.

## Features

- **Format Support**: Ingests `.mp3`, `.m4a`, `.flac`, `.wav`, `.aac`, and `.ogg`.
- **Filename Sanitization**: Normalizes Unicode representations, strips troublesome filesystem characters, and standardizes spacing and separators.
- **Collision Protection**: Automatically increments destination filenames to prevent accidental overwrites.
- **Monitoring Mode**: Continuously watches a designated staging directory and routes stable files.
- **Spotify Integration**: Points by default to `~/Music/SpotifyLocal`, ready to be added as a source in Spotify Settings -> Local Files.

## Usage

### Batch Scan

Process all pending tracks in a staging folder:

```bash
python3 scripts/organize-local-audio.py --source ~/Downloads/AudioStaging --destination ~/Music/SpotifyLocal
```

### Background Watch Mode

Continuously monitor a folder for new incoming files:

```bash
python3 scripts/organize-local-audio.py --source ~/Downloads/AudioStaging --destination ~/Music/SpotifyLocal --watch
```
