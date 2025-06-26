#!/bin/bash

# Uses fabric repo to create YouTube transcripts amongst other magic: https://github.com/danielmiessler/fabric

VideoURL="https://www.youtube.com/watch?v=FtnGiI9MGgA"
LANG="en"
TranscriptFile="$(mktemp)"
yt-dlp --quiet --no-warnings --write-auto-sub --sub-lang $LANG --skip-download --sub-format vtt -o "$TranscriptFile" "$VideoURL"
TranscriptFile="$TranscriptFile.$LANG.vtt"
cat $TranscriptFile
#srm $TranscriptFile