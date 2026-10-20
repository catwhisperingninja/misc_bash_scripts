#!/bin/bash
set -o pipefail

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

# YouTube rate-limits timedtext (HTTP 429).
# Fast path: browser TLS impersonation (curl_cffi) usually avoids 429 with ~0s sleep.
# Slow path: short sleep only on retry (5s, then 10s max — never 60s by default).
# See: https://github.com/yt-dlp/yt-dlp/issues/13831
#
# Env overrides:
#   YT_SLEEP_SUBTITLES=0|5|10   base sleep before timedtext (default 0)
#   YT_IMPERSONATE=chrome|""    yt-dlp --impersonate target (default chrome)
#   YT_SUB_LANGS="en-orig en"   language try order
SLEEP_SUBS="${YT_SLEEP_SUBTITLES:-0}"
IMPERSONATE="${YT_IMPERSONATE-chrome}"
SUB_LANG_CANDIDATES="${YT_SUB_LANGS:-en-orig en}"
# Retry sleeps escalate quickly, capped for interactive use
RETRY_SLEEPS="${YT_RETRY_SLEEPS:-5 10}"
dl_ok=0
last_err=""

has_sub_file_for_lang() {
    local lang="$1"
    find . -maxdepth 1 \( \
        -name "*$video_id*.$lang.vtt" -o -name "*$video_id*.$lang.srt" -o \
        -name "*$video_id*.vtt" -o -name "*$video_id*.srt" \
    \) 2>/dev/null | grep -q .
}

run_ytdlp_subs() {
    local lang="$1" sleep_s="$2"
    local -a cmd
    cmd=(yt-dlp --write-subs --write-auto-subs --skip-download
         --sub-langs "$lang"
         --sub-format "vtt/srt/best"
         --retries 2
         --retry-sleep 2)
    if [ -n "$IMPERSONATE" ]; then
        cmd+=(--impersonate "$IMPERSONATE")
    fi
    if [ "${sleep_s:-0}" -gt 0 ] 2>/dev/null; then
        cmd+=(--sleep-subtitles "$sleep_s")
    fi
    cmd+=("$url")
    "${cmd[@]}"
}

for lang in $SUB_LANG_CANDIDATES; do
    # attempt plan: base sleep, then short retries only
    sleep_plan="$SLEEP_SUBS $RETRY_SLEEPS"
    attempt=0
    for sleep_s in $sleep_plan; do
        attempt=$((attempt + 1))
        if [ "$sleep_s" -gt 0 ] 2>/dev/null; then
            echo "Trying lang='$lang' attempt $attempt (impersonate=${IMPERSONATE:-none}, sleep ${sleep_s}s)..."
        else
            echo "Trying lang='$lang' attempt $attempt (impersonate=${IMPERSONATE:-none}, no sleep)..."
        fi

        err_log=$(mktemp)
        if run_ytdlp_subs "$lang" "$sleep_s" 2>&1 | tee "$err_log"; then
            if has_sub_file_for_lang "$lang"; then
                rm -f "$err_log"
                dl_ok=1
                break 2
            fi
        fi

        last_err=$(cat "$err_log")
        if grep -qiE 'HTTP Error 429|Too Many Requests' "$err_log"; then
            rm -f "$err_log"
            echo "Rate limited (HTTP 429); escalating short sleep if available..."
            continue
        fi

        rm -f "$err_log"
        # Non-429 for this lang: try next language
        break
    done

    [ "$dl_ok" -eq 1 ] && break
done

if [ "$dl_ok" -ne 1 ]; then
    echo "Error: Failed to download subtitles after trying: $SUB_LANG_CANDIDATES"
    if printf '%s' "$last_err" | grep -qiE 'HTTP Error 429|Too Many Requests'; then
        echo "YouTube is still rate-limiting timedtext downloads."
        echo "Fast options: YT_SLEEP_SUBTITLES=5  or  cookies from a logged-in browser:"
        echo "  yt-dlp --cookies-from-browser chrome --impersonate chrome --write-auto-subs --skip-download --sub-langs en-orig URL"
    else
        echo "The video may not have subtitles available or may be restricted."
    fi
    exit 1
fi

# Prefer original-language auto caps, then plain en, then any match.
subtitle_file=$({
    find . -maxdepth 1 \( -name "*$video_id*.en-orig.vtt" -o -name "*$video_id*.en-orig.srt" \)
    find . -maxdepth 1 \( -name "*$video_id*.en.vtt" -o -name "*$video_id*.en.srt" \)
    find . -maxdepth 1 \( -name "*$video_id*.srt" -o -name "*$video_id*.vtt" \)
} 2>/dev/null | awk 'NF && !seen[$0]++' | head -1)

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

# Derive a hyphenated title and finalize file naming, then prepend metadata
title=$(yt-dlp --skip-download --get-title "$url" 2>/dev/null | head -n 1)
if [ -z "$title" ]; then
    title="$video_id"
fi

# Build a safe hyphenated slug
slug=$(printf '%s' "$title" | sed -E 's/[[:space:]]+/-/g; s/[^A-Za-z0-9._-]+//g; s/-{2,}/-/g; s/^-+|-+$//g')
if [ -z "$slug" ]; then
    slug="$video_id"
fi

dest="${slug}.txt"
if [ -e "$dest" ]; then
    n=1
    while [ -e "${slug}-${n}.txt" ]; do
        n=$((n+1))
    done
    dest="${slug}-${n}.txt"
fi

tmpfile=$(mktemp)
{
    printf 'URL: %s\n' "$url"
    printf 'Title: %s\n' "$slug"
    cat clean_transcript.txt
} > "$tmpfile"

mv "$tmpfile" "$dest"
rm -f clean_transcript.txt
echo "Final transcript saved to $dest"
