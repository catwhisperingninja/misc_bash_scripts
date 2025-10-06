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
    # Try live URL format
    video_id=$(echo "$url" | sed -n 's|.*live/\([^?]*\).*|\1|p' | head -c 11)
fi

if [ -z "$video_id" ]; then
    echo "Error: Could not extract video ID from URL"
    exit 1
fi

echo "Processing video ID: $video_id"

# Clean up any existing files for this video ID
rm -f *"$video_id"*.srt *"$video_id"*.vtt

# Download subtitles (prefer SRT for easier parsing; convert if needed)
if ! yt-dlp --write-auto-subs --skip-download --sub-langs en --sub-format srt --convert-subs srt "$url"; then
    echo "Error: Failed to download subtitles. The video may not have subtitles available or may be restricted."
    exit 1
fi

# Find subtitle file for this specific video (prefer .srt)
subtitle_file=$(find . -name "*$video_id*.srt" -o -name "*$video_id*.vtt" | head -1)

if [ -z "$subtitle_file" ]; then
    echo "Error: No subtitle files found for video ID $video_id. The video may not have subtitles available."
    exit 1
fi

echo "Found subtitle file: $subtitle_file"

# Clean the transcript: one line per cue -> "START_TIME TEXT"
# Supports both SRT and VTT by scanning blocks separated by blank lines
awk 'BEGIN{RS=""; FS="\n"}
{
  start=""; text="";
  for(i=1;i<=NF;i++){
    line=$i;
    # Skip headers and pure cue indices
    if(line ~ /^(WEBVTT|Kind:|Language:|NOTE)/) continue;
    if(line ~ /^[[:space:]]*[0-9]+[[:space:]]*$/) continue;

    # Capture start time from timecode line (SRT or VTT)
    if(line ~ /-->/){
      if (match(line, /[0-9]{2}:[0-9]{2}:[0-9]{2}[,.][0-9]{3}/)){
        start=substr(line, RSTART, RLENGTH);
        gsub(",",".",start);
      }
      continue;
    }

    # Accumulate cue text lines, stripping simple tags like <c> and any <...>
    gsub(/<[^>]*>/, "", line);
    if(length(line) == 0) continue;
    if(text == "") text=line; else text=text " " line;
  }
  if(start != "" && text != ""){
    print start " " text;
  }
}' "$subtitle_file" > clean_transcript.txt

echo "Clean transcript saved to clean_transcript.txt"
