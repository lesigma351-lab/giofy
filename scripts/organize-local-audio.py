#!/usr/bin/env python3
"""
Convenience CLI runner for audio_pipeline.
Usage:
    python3 scripts/organize-local-audio.py --source ~/Downloads/Music
"""

import sys
from pathlib import Path

# Add scripts directory to sys.path
sys.path.insert(0, str(Path(__file__).parent))

from audio_pipeline.__main__ import main

if __name__ == "__main__":
    main()
