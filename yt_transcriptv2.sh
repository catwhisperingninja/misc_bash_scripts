#!/bin/bash

# YouTube transcript extractor with error handling
url="$1"

if [ -z "$url" ]; then
    echo "Usage: $0 <youtube_url>"
    exit 1
fi

# Extract video ID from URL
video_id=$(echo "$url" | sed -n 's/.*[?&]v=\([^&]*\).*/\1/p' | head -c 11)
if [ -z "$video_id" ]; then
    # Try youtu.be format
    video_id=$(echo "$url" | sed -n 's|.*youtu.be/\([^?]*\).*|\1|p' | head -c 11)
fi

if [ -z "$video_id" ]; then
    echo "Error: Could not extract video ID from URL"
    exit 1
fi

echo "Processing video ID: $video_id"

# Clean up any existing files for this video ID
rm -f *"$video_id"*.srt *"$video_id"*.vtt

# Download subtitles (any available format)
if ! yt-dlp --write-auto-subs --skip-download --sub-langs en "$url"; then
    echo "Error: Failed to download subtitles. The video may not have subtitles available or may be restricted."
    exit 1
fi

# Find subtitle file for this specific video
subtitle_file=$(find . -name "*$video_id*.vtt" -o -name "*$video_id*.srt" | head -1)

if [ -z "$subtitle_file" ]; then
    echo "Error: No subtitle files found for video ID $video_id. The video may not have subtitles available."
    exit 1
fi

echo "Found subtitle file: $subtitle_file"

# Clean the transcript
grep -v "^[0-9]*$" "$subtitle_file" | \
grep -v "^[0-9][0-9]:[0-9][0-9]:[0-9][0-9]" | \
grep -v "^$" | \
grep -v "^WEBVTT" | \
grep -v "^NOTE" > clean_transcript.txt

echo "Clean transcript saved to clean_transcript.txt"
