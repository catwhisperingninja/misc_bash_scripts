#!/bin/bash

# Generate a transcript from a YouTube video
# Uses yt-dlp to download the video and then uses the transcript file to generate a transcript

VideoURL="https://youtu.be/oqUclC3gqKs"
LANG="en"
TranscriptFile="$(mktemp)"
yt-dlp --quiet --no-warnings --write-auto-sub --sub-lang $LANG --skip-download --sub-format vtt -o "$TranscriptFile" "$VideoURL"
TranscriptFile="$TranscriptFile.$LANG.vtt"
cat $TranscriptFile
#srm $TranscriptFile