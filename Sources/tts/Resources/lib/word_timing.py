"""Word timing extraction for Kokoro TTS.

Provides functions for extracting word timings from Kokoro pipeline tokens.
"""

from typing import Any

# Punctuation tags that should be filtered from word timings
PUNCTUATION_TAGS = frozenset({'.', ',', '!', '?', ':', ';', '-', '(', ')'})


def is_punctuation_only(token: Any) -> bool:
    """Check if token is punctuation that should be skipped.
    
    A token is considered punctuation-only if:
    1. Its tag is in the PUNCTUATION_TAGS set
    2. Its text content is 1 character or less (after stripping whitespace)
    
    This allows words like "Mr." to be kept while skipping standalone punctuation.
    
    Args:
        token: A Kokoro pipeline token with 'tag' and 'text' attributes.
        
    Returns:
        True if the token should be skipped as punctuation.
    """
    return token.tag in PUNCTUATION_TAGS and len(token.text.strip()) <= 1


def extract_word_timings(tokens: list[Any], current_time: float) -> list[dict]:
    """Extract word timings from tokens, filtering punctuation.
    
    Processes a list of Kokoro pipeline tokens and extracts timing information
    for each word, adding the current_time offset to account for previous chunks.
    
    Args:
        tokens: List of Kokoro pipeline tokens with tag, text, start_ts, end_ts.
        current_time: Time offset in seconds from previous audio chunks.
        
    Returns:
        List of timing dictionaries with 'word', 'start', and 'end' keys.
    """
    timings = []
    for token in tokens:
        # Skip punctuation-only tokens
        if is_punctuation_only(token):
            continue
        
        # Skip tokens with missing timestamps
        if token.start_ts is None or token.end_ts is None:
            continue
        
        timings.append({
            "word": token.text,
            "start": current_time + token.start_ts,
            "end": current_time + token.end_ts,
        })
    
    return timings
