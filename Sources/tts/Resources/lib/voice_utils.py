"""Voice file utilities for Kokoro TTS.

Provides shared constants and functions for working with voice files.
"""

import os

# Supported voice file extensions in priority order
VOICE_EXTENSIONS = (".pt", ".onnx", ".bin")


def is_voice_file(filename: str) -> bool:
    """Check if filename is a voice file.
    
    Args:
        filename: The filename or path to check.
        
    Returns:
        True if the file has a valid voice extension.
    """
    return filename.endswith(VOICE_EXTENSIONS)


def get_voice_name(path: str) -> str:
    """Extract voice name from file path.
    
    Args:
        path: Full path or filename of the voice file.
        
    Returns:
        The voice name without extension (e.g., "af_heart").
    """
    return os.path.splitext(os.path.basename(path))[0]


def voice_patterns_for(voice: str) -> list[str]:
    """Generate allow_patterns for a specific voice.
    
    Args:
        voice: The voice name (e.g., "af_heart").
        
    Returns:
        List of patterns for all possible voice file extensions.
    """
    return [f"voices/{voice}{ext}" for ext in VOICE_EXTENSIONS]
